import PA1Helper
import System.Environment (getArgs)
import PA1Helper (Lexp)

-- Haskell representation of lambda expression
-- data Lexp = Atom String | Lambda String Lexp | Apply Lexp  Lexp

-- Given a filename and function for reducing lambda expressions,
-- reduce all valid lambda expressions in the file and output results.
-- runProgram :: String -> (Lexp -> Lexp) -> IO ()

-- This is the identity function for the Lexp datatype, which is
-- used to illustrate pattern matching with the datatype. "_" was
-- used since I did not need to use bound variable. For your code,
-- however, you can replace "_" with an actual variable name so you
-- can use the bound variable. The "@" allows you to retain a variable
-- that represents the entire structure, while pattern matching on
-- components of the structure.
id' :: Lexp -> Lexp
id' v@(Atom _) = v
id' lexp@(Lambda _ _) = lexp
id' lexp@(Apply _ _) = lexp

-- You will need to write a reducer that does something more than
-- return whatever it was given, of course!

reducer :: Lexp -> Lexp
reducer lexp = fullEtaReduce (betaReduce lexp)

--Checks if the variable is free
freeVar :: String -> Lexp -> Bool
freeVar var (Atom name) = var == name
freeVar var (Lambda exp1 exp2)
    |var == exp1 = False
    |otherwise = freeVar var exp2
freeVar var (Apply exp1 exp2) =
    (freeVar var exp1) || (freeVar var exp2)

--Eta Reducer
etaReduce :: Lexp -> Lexp
etaReduce (Lambda exp (Apply func (Atom arg)))
    |exp == arg && not (freeVar exp func) = func
etaReduce (Lambda exp1 exp2) =
    Lambda exp1 (etaReduce exp2)
etaReduce (Apply exp1 exp2) =
    Apply (etaReduce exp1) (etaReduce exp2)
etaReduce (Atom name) = Atom name

fullEtaReduce :: Lexp -> Lexp
fullEtaReduce exp
    |next == exp = exp
    |otherwise = fullEtaReduce next
    where
        next = etaReduce exp

--substitute function
substitute :: String -> Lexp -> Lexp -> Lexp
substitute var replace (Atom name)
    |var == name = replace
    |otherwise = Atom name
substitute var replace (Lambda bound body)
    |var == bound = Lambda bound body
    |not (freeVar bound replace) =
        Lambda bound (substitute var replace body)
    | otherwise =
         let used = allVars body ++ allVars replace ++ [var, bound]
             fresh = freshVar used
             renamedBody = alphaRename bound fresh body
         in Lambda fresh (substitute var replace renamedBody)
substitute var replace(Apply exp1 exp2) =
    Apply (substitute var replace exp1)
          (substitute var replace exp2)

--function that gets every used variable
allVars :: Lexp -> [String]
allVars (Atom name) = [name]
allVars (Lambda bound body) = bound : allVars body
allVars (Apply left right) =
    allVars left ++ allVars right

--fresh name generator
freshVar :: [String] -> String
freshVar used = findFresh 0
    where
        findFresh n
            | candidate `notElem` used = candidate
            | otherwise = findFresh (n + 1)
            where
                candidate = "v" ++ show n

alphaRename :: String -> String -> Lexp -> Lexp
alphaRename old new (Atom name)
    | name == old = Atom new
    | otherwise   = Atom name
alphaRename old new (Apply exp1 exp2) =
    Apply (alphaRename old new exp1)
          (alphaRename old new exp2)
alphaRename old new lexp@(Lambda bound body)
    |bound == old = lexp
    |otherwise = Lambda bound (alphaRename old new body)

--Beta reducer
betaReduce :: Lexp -> Lexp
betaReduce (Atom v) = Atom v
betaReduce (Lambda v e) = Lambda v (betaReduce e)
betaReduce (Apply (Lambda v body) arg) = betaReduce (substitute v arg body)
betaReduce (Apply e1 e2) = combine (betaReduce e1) e2
  where
    combine (Lambda v body) arg = betaReduce (substitute v arg body)
    combine other arg = Apply other (betaReduce arg)

-- Entry point of program
main = do
    args <- getArgs
    let inFile = case args of { x:_ -> x; _ -> "input.lambda" }
    let outFile = case args of { x:y:_ -> y; _ -> "output.lambda"}
    -- id' simply returns its input, so runProgram will result
    -- in printing each lambda expression twice.
    runProgram inFile outFile reducer
