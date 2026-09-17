# Programming Assignment 1: Lambda Calculus Interpreter

**CSCI 4430/6430 - Programming Languages**
Fall 2026

> **Due:** 7:00 PM, Monday, September 21, 2026

## Collaboration Policy

Complete this assignment either individually or in a pair. Do not show your code to another group or look at another group's code. Do not make your code public, including by placing it in a public repository or directory.

You may get help from mentors, TAs, or the instructor. You are encouraged to use the Submitty Discussion Forum to post questions so that other students can see and answer them.

## Goal

Write a lambda calculus interpreter in a functional programming language. It must reduce lambda calculus expressions using **call-by-name (normal-order)** evaluation.

For each expression, repeatedly perform beta reduction until it is no longer possible. Then repeatedly perform eta reduction until it is no longer possible.

## Lambda Calculus Grammar

```text
<expression> ::= <atom>
               | "\\" <atom> "." <expression>
               | "(" <expression> " " <expression> ")"
```

An `<atom>` is a lowercase alphanumeric string that begins with a letter.

## Input and Output

Your program reads lambda calculus expressions from a text file, with **one expression per line**, and processes them in sequence. A parser and supporting input/output code are provided so that you can focus on lambda calculus semantics.

Your program must accept exactly two command-line arguments:

1. The input filename, containing lambda calculus expressions.
2. The output filename, to receive the reduced expressions.

Write one reduced expression per line to the output file. If an expression cannot be reduced, write exactly one blank line for that expression and continue with the next one.

> Do not write debug output, test numbers, or any other extra lines. Writing more than one line—or no line at all—for an input expression will interfere with autograding.

## Implementation Guidance

You may—and should—define auxiliary procedures for alpha-renaming, beta reduction, eta conversion, and substitution.

When substituting during beta reduction, ensure that free variables in the replacement expression are not captured. Recall that with call-by-name evaluation, a function argument is not evaluated until it is used within the function body.

You may choose any variable names when alpha-renaming, provided they satisfy the `<atom>` definition. Your code is correct if its result can be made to match the expected result by renaming zero or more variables.

## Sample Interpretations

The following examples are also available in `input.lambda`.

| Expression | Result | Comment |
| --- | --- | --- |
| `(\x.x y)` | `y` | Identity combinator |
| `\x.(y x)` | `y` | Eta reduction |
| `(\x.\y.(y x) (y w))` | `\z.(z (y w))` | Avoid capturing the free variable `y` in `(y w)` |
| `(\x.\y.(x y) (y w))` | `(y w)` | Avoid capturing the free variable `y` in `(y w)`; then perform eta reduction |
| `((\y.\x.(y x) \x.(x x)) y)` | `(y y)` | Application combinator |
| `(((\b.\t.\e.((b t) e) \x.\y.x) x) y)` | `x` | If-then-else combinator |
| `\x.((\x.(y x) \x.(z x)) x)` | `(y z)` | Eta reductions |
| `(\y.(\x.\y.(x y) y) (y w))` | `(y w)` | Alpha-renaming, beta reduction, and eta reduction |

## Haskell Starter Code

We provide `main.hs` and `PA1Helper.hs`. The helper file reads lambda calculus expressions from an input file and parses them into the `Lexp` datatype; see `runProgram` in particular. The `Lexp` type constructors are exported and should be used to pattern-match lambda expressions.

Implement a reducer function in `main.hs` that accepts an `Lexp` and returns an `Lexp`.

```haskell
reducer :: Lexp -> Lexp
```

The provided helper code writes both to standard output and the output file. Standard output is intended for development; only the lines written to the output file are graded.

Keep the filename `main.hs`. It already contains the required two-argument command-line interface. Edit only `main.hs`, since it is the only Haskell file you will submit.

### Sample Interaction

```console
$ cat sample.lambda
(\x.x y)
(\x.\y.(x y) (y w))

$ runghc main.hs sample.lambda output.lambda

$ cat output.lambda
y
(y w)
```

### Additional Haskell Hints

`Data.Map` and `Data.Set` may be useful. Hoogle is a useful search engine for Haskell documentation.

If you receive an error stating that `Text.Parsec` is undefined, run:

```console
stack install parsec
# or
cabal install parsec
```

## Grading

Grading is based primarily on correctness, with code clarity and readability also considered. Comment every function and provide type signatures where appropriate. If a part of your code is unclear, explain it with comments.

Correctness is determined by whether your result is alpha-equivalent to the expected expression. Therefore, your alpha-renamed variables may have different names, as long as they are valid lowercase alphanumeric strings that begin with a letter.

This assignment requires a lambda calculus interpreter. Hard-coding known inputs—for example, with `if`/`else` cases—will result in a severe point reduction.

## Submission Requirements

Submit only:

- `main.hs`
- `README`

In `README`, include the names of all group members (up to two) and a list of specific known features and bugs in your solution.

## Submitty Team Creation

Create a team in Submitty whether you complete the assignment alone or with a partner. Team creation locks at **7:00 PM on Monday, September 14, 2026**, one week before the assignment is due.
