---------------------------------------------------------------------------------
-- |
-- Module      :  Data.SBV.Dynamic
-- Copyright   :  (c) Brian Huffman
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
--
-- Dynamically typed low-level API to the SBV library, for users who
-- want to generate symbolic values at run-time. Note that with this
-- API it is possible to create terms that are not type correct; use
-- at your own risk!
---------------------------------------------------------------------------------

module Data.SBV.Dynamic
  (
  -- * Programming with symbolic values
  -- ** Symbolic types
  -- *** Abstract symbolic value type
    SVal
  , HasKind(..), Kind(..), CW(..), CWVal(..), cwToBool
  -- *** Arrays of symbolic values
  , SArr, readSArr, writeSArr, mergeSArr, newSArr, eqSArr

  -- ** Creating a symbolic variable
  , Symbolic
  , Quantifier(..)
  , svMkSymVar
  -- ** Operations on symbolic values
  -- *** Boolean literals
  , svTrue, svFalse, svBool, svAsBool
  -- *** Integer literals
  , svInteger, svAsInteger
  -- *** Float literals
  , svFloat, svDouble
  -- *** Algebraic reals (only from rationals)
  , svReal, svNumerator, svDenominator
  -- *** Symbolic equality
  , svEqual, svNotEqual
  -- *** Constructing concrete lists
  , svEnumFromThenTo
  -- *** Symbolic ordering
  , svLessThan, svGreaterThan, svLessEq, svGreaterEq
  -- *** Arithmetic operations
  , svPlus, svTimes, svMinus, svUNeg, svAbs
  , svDivide, svQuot, svRem, svExp
  , svAddConstant, svIncrement, svDecrement
  -- *** Logical operations
  , svAnd, svOr, svXOr, svNot
  , svShl, svShr, svRol, svRor
  -- *** Splitting, joining, and extending
  , svExtract, svJoin
  -- *** Sign-casting
  , svSign, svUnsign
  -- *** Numeric conversions
  , svFromIntegral
  -- *** Indexed lookups
  , svSelect
  -- *** Word-level operations
  , svToWord1, svFromWord1, svTestBit, svSetBit
  , svShiftLeft, svShiftRight
  , svRotateLeft, svRotateRight
  , svWordFromBE, svWordFromLE
  , svBlastLE, svBlastBE
  -- ** Conditionals: Mergeable values
  , svIte, svLazyIte, svSymbolicMerge
  , svIsSatisfiableInCurrentPath
  -- * Uninterpreted sorts, constants, and functions
  , svUninterpreted
  -- * Properties, proofs, and satisfiability
  -- ** Proving properties
  , proveWith
  -- ** Checking satisfiability
  , satWith, allSatWith
  -- ** Checking safety
  , safeWith
  -- * Proving properties using multiple solvers
  , proveWithAll, proveWithAny, satWithAll, satWithAny
  -- * Quick-check
  , svQuickCheck

  -- * Model extraction

  -- ** Inspecting proof results
  , ThmResult(..), SatResult(..), AllSatResult(..), SafeResult(..), OptimizeResult(..), SMTResult(..)

  -- ** Programmable model extraction
  , genParse, getModelAssignment, getModelDictionary
  -- * SMT Interface: Configurations and solvers
  , SMTConfig(..), SMTLibVersion(..), Solver(..), SMTSolver(..), boolector, cvc4, yices, z3, mathSAT, abc, defaultSolverConfig, defaultSMTCfg, sbvCheckSolverInstallation, sbvAvailableSolvers

  -- * Symbolic computations
  , outputSVal

  -- * Code generation from symbolic programs
  , SBVCodeGen

  -- ** Setting code-generation options
  , cgPerformRTCs, cgSetDriverValues, cgGenerateDriver, cgGenerateMakefile

  -- ** Designating inputs
  , svCgInput, svCgInputArr

  -- ** Designating outputs
  , svCgOutput, svCgOutputArr

  -- ** Designating return values
  , svCgReturn, svCgReturnArr

  -- ** Code generation with uninterpreted functions
  , cgAddPrototype, cgAddDecl, cgAddLDFlags, cgIgnoreSAssert

  -- ** Code generation with 'SInteger' and 'SReal' types
  , cgIntegerSize, cgSRealType, CgSRealType(..)

  -- ** Compilation to C
  , compileToC, compileToCLib

  -- ** Compilation to SMTLib
  , compileToSMTLib, generateSMTBenchmarks
  ) where

import Data.Map (Map)

import Data.SBV.Core.Kind
import Data.SBV.Core.Concrete
import Data.SBV.Core.Symbolic
import Data.SBV.Core.Operations

import Data.SBV.Compilers.CodeGen ( SBVCodeGen
                                  , svCgInput, svCgInputArr
                                  , svCgOutput, svCgOutputArr
                                  , svCgReturn, svCgReturnArr
                                  , cgPerformRTCs, cgSetDriverValues, cgGenerateDriver, cgGenerateMakefile
                                  , cgAddPrototype, cgAddDecl, cgAddLDFlags, cgIgnoreSAssert
                                  , cgIntegerSize, cgSRealType, CgSRealType(..)
                                  )
import Data.SBV.Compilers.C       (compileToC, compileToCLib)

import Data.SBV.Provers.Prover (boolector, cvc4, yices, z3, mathSAT, abc, defaultSMTCfg)
import Data.SBV.SMT.SMT        (ThmResult(..), SatResult(..), SafeResult(..), OptimizeResult(..), AllSatResult(..), genParse)
import Data.SBV                (sbvCheckSolverInstallation, defaultSolverConfig, sbvAvailableSolvers)

import qualified Data.SBV                as SBV (SBool, proveWithAll, proveWithAny, satWithAll, satWithAny)
import qualified Data.SBV.Core.Data      as SBV (SBV(..))
import qualified Data.SBV.Core.Model     as SBV (isSatisfiableInCurrentPath, sbvQuickCheck)
import qualified Data.SBV.Provers.Prover as SBV (proveWith, satWith, safeWith, allSatWith, compileToSMTLib, generateSMTBenchmarks)
import qualified Data.SBV.SMT.SMT        as SBV (Modelable(getModelAssignment, getModelDictionary))

import Data.Time (NominalDiffTime)

-- | Reduce a condition (i.e., try to concretize it) under the given path
svIsSatisfiableInCurrentPath :: SVal -> Symbolic (Maybe SatResult)
svIsSatisfiableInCurrentPath = SBV.isSatisfiableInCurrentPath . toSBool

-- | Dynamic variant of quick-check
svQuickCheck :: Symbolic SVal -> IO Bool
svQuickCheck = SBV.sbvQuickCheck . fmap toSBool

toSBool :: SVal -> SBV.SBool
toSBool = SBV.SBV

-- | Compiles to SMT-Lib and returns the resulting program as a string. Useful for saving
-- the result to a file for off-line analysis, for instance if you have an SMT solver that's not natively
-- supported out-of-the box by the SBV library. It takes two arguments:
--
--    * version: The SMTLib-version to produce. Note that we currently only support SMTLib2.
--
--    * isSat  : If 'True', will translate it as a SAT query, i.e., in the positive. If 'False', will
--               translate as a PROVE query, i.e., it will negate the result. (In this case, the check-sat
--               call to the SMT solver will produce UNSAT if the input is a theorem, as usual.)
compileToSMTLib :: SMTLibVersion   -- ^ If True, output SMT-Lib2, otherwise SMT-Lib1
                -> Bool            -- ^ If True, translate directly, otherwise negate the goal. (Use True for SAT queries, False for PROVE queries.)
                -> Symbolic SVal
                -> IO String
compileToSMTLib version isSat s = SBV.compileToSMTLib version isSat (fmap toSBool s)

-- | Create both SMT-Lib1 and SMT-Lib2 benchmarks. The first argument is the basename of the file,
-- SMT-Lib1 version will be written with suffix ".smt1" and SMT-Lib2 version will be written with
-- suffix ".smt2". The 'Bool' argument controls whether this is a SAT instance, i.e., translate the query
-- directly, or a PROVE instance, i.e., translate the negated query. (See the second boolean argument to
-- 'compileToSMTLib' for details.)
generateSMTBenchmarks :: Bool -> FilePath -> Symbolic SVal -> IO ()
generateSMTBenchmarks isSat f s = SBV.generateSMTBenchmarks isSat f (fmap toSBool s)

-- | Proves the predicate using the given SMT-solver
proveWith :: SMTConfig -> Symbolic SVal -> IO ThmResult
proveWith cfg s = SBV.proveWith cfg (fmap toSBool s)

-- | Find a satisfying assignment using the given SMT-solver
satWith :: SMTConfig -> Symbolic SVal -> IO SatResult
satWith cfg s = SBV.satWith cfg (fmap toSBool s)

-- | Check safety using the given SMT-solver
safeWith :: SMTConfig -> Symbolic SVal -> IO [SafeResult]
safeWith cfg s = SBV.safeWith cfg (fmap toSBool s)

-- | Find all satisfying assignments using the given SMT-solver
allSatWith :: SMTConfig -> Symbolic SVal -> IO AllSatResult
allSatWith cfg s = SBV.allSatWith cfg (fmap toSBool s)

-- | Prove a property with multiple solvers, running them in separate threads. The
-- results will be returned in the order produced.
proveWithAll :: [SMTConfig] -> Symbolic SVal -> IO [(Solver, NominalDiffTime, ThmResult)]
proveWithAll cfgs s = SBV.proveWithAll cfgs (fmap toSBool s)

-- | Prove a property with multiple solvers, running them in separate
-- threads. Only the result of the first one to finish will be
-- returned, remaining threads will be killed.
proveWithAny :: [SMTConfig] -> Symbolic SVal -> IO (Solver, NominalDiffTime, ThmResult)
proveWithAny cfgs s = SBV.proveWithAny cfgs (fmap toSBool s)

-- | Find a satisfying assignment to a property with multiple solvers,
-- running them in separate threads. The results will be returned in
-- the order produced.
satWithAll :: [SMTConfig] -> Symbolic SVal -> IO [(Solver, NominalDiffTime, SatResult)]
satWithAll cfgs s = SBV.satWithAll cfgs (fmap toSBool s)

-- | Find a satisfying assignment to a property with multiple solvers,
-- running them in separate threads. Only the result of the first one
-- to finish will be returned, remaining threads will be killed.
satWithAny :: [SMTConfig] -> Symbolic SVal -> IO (Solver, NominalDiffTime, SatResult)
satWithAny cfgs s = SBV.satWithAny cfgs (fmap toSBool s)

-- | Extract a model, the result is a tuple where the first argument (if True)
-- indicates whether the model was "probable". (i.e., if the solver returned unknown.)
getModelAssignment :: SMTResult -> Either String (Bool, [CW])
getModelAssignment = SBV.getModelAssignment

-- | Extract a model dictionary. Extract a dictionary mapping the variables to
-- their respective values as returned by the SMT solver. Also see `getModelDictionaries`.
getModelDictionary :: SMTResult -> Map String CW
getModelDictionary = SBV.getModelDictionary
