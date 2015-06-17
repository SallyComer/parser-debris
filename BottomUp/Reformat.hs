module Reformat (on, translate, doItAll) where

import Tokenize
import TokenMonad
import Control.Applicative
import CommonData

import Data.List


-- Turns all operators into function calls
-- Uses shunting yard thingy?

-- Left associative works from left to right
-- Right associative works from right to left





getPrec :: Prec -> Int
getPrec (L _ i) = i
getPrec (R _ i) = i




data Inter = Ap Inter Inter | Single Token | Group [Inter] | Abs' String Inter deriving (Show, Eq)



applic :: Inter -> Consumer Token Inter
applic thing = do
    blah <- getSingle <|> getParens
    return $ Ap thing blah


getSingle = fmap Single (sat isId <|> sat isLit)

getOperator = fmap Single (sat isOp)


getApplication' thing = do
    blah <- applic thing
    getApplication' blah <|> return blah

getApplication :: Consumer Token Inter
getApplication = do
    thing <- getSingle
    getApplication' thing

getAbs :: Consumer Token Inter
getAbs = do
    sat (== LambdaStart)
    (Id n) <- sat isId
    sat (== LambdaArrow)
    blah <- some getWhole
    return (Abs' n (Group blah))
    


getWhole = getApplication <|> getSingle <|> getOperator <|> getParens

getParens = do
    sat (== LParen)
    things <- many getWhole
    sat (== RParen)
    return (Group things)


doThing :: [Token] -> [Inter]
doThing str = case terminal (many getWhole) str of
    Just a -> a
    Nothing -> error "parse error"

f `on` blah = \a b -> f (blah a) (blah b)

-- 0 is worst
distanceFrom things (L op _) = case findIndex (== Single (Op op)) (reverse things) of
    Just a -> a
    Nothing -> 0
distanceFrom things (R op _) = case findIndex (== Single (Op op)) things of
    Just a -> a
    Nothing -> 0

highestPrec precs things = last $ sortBy (compare `on` distanceFrom things) precs' where
    precs' = head $ dropWhile (not . any (containedIn things)) $ groupBy ((==) `on` getPrec) $ sortBy (compare `on` getPrec) precs

containedIn :: [Inter] -> Prec -> Bool
containedIn things (L a _) = any (== Single (Op a)) things
containedIn things (R a _) = any (== Single (Op a)) things

findPlace :: Prec -> [Inter] -> Maybe Int
findPlace (L op _) things = findIndex (== Single (Op op)) things
findPlace (R op _) things = case findIndices (== Single (Op op)) things of
    [] -> Nothing
    blah -> Just $ last blah

reorganize :: [Prec] -> [Inter] -> Inter
reorganize precs things
 | any (\a -> case a of {Single (Op _) -> True; _ -> False}) things =
  case findPlace (highestPrec precs things) things of
   Just ind -> delve precs $ Ap (Ap theThingItself before) after where
    before = reorganize precs $ take ind things
    after = reorganize precs $ drop (ind + 1) things
    theThingItself = things !! ind
   Nothing -> Group (map (delve precs) things)
 | length things == 1 = delve precs (head things)
 | otherwise = Group things


delve precs (Group a) = reorganize precs a
delve precs (Ap a b) = Ap (delve precs a) (delve precs b)
delve precs (Single a) = Single a




reify' :: Inter -> [Token]
reify' (Group [Single a]) = [a]
reify' (Group [Group a]) = reify' (Group a)
reify' (Group a) = LParen : (reify a) ++ [RParen]
reify' (Single a) = [a]
reify' (Ap a b) = LParen : reify' a ++ reify' b ++ [RParen]
reify' (Abs' n (Group [a])) = reify' (Abs' n a)
reify' (Abs' n a) = LParen : Id n : reify' a ++ [RParen]

reify = (>>= reify')


doItAll :: [Prec] -> [Token] -> ParseTree
doItAll precs toks = translate $ reorganize precs (doThing toks)






translate :: Inter -> ParseTree
translate (Single a) = Atom a
translate (Ap a b) = Apply (translate a) (translate b)
translate (Group [a]) = translate a
translate (Group what) = error $ "Parse error? check translate " ++ show what
translate (Abs' n blah) = Abs n (translate blah)

