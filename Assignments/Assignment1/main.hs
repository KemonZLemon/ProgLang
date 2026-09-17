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
reducer lexp = fullEtaReduce lexp

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

-- Entry point of program
main = do
    args <- getArgs
    let inFile = case args of { x:_ -> x; _ -> "input.lambda" }
    let outFile = case args of { x:y:_ -> y; _ -> "output.lambda"}
    -- id' simply returns its input, so runProgram will result
    -- in printing each lambda expression twice.
    runProgram inFile outFile reducer
