module Test.Kore.Step.Simplification
    ( Simplifier, Env (..)
    , runSimplifier
    , runSimplifierNoSMT
    , runSimplifierBranch
    , simplifiedCondition
    , simplifiedOrCondition
    , simplifiedOrPattern
    , simplifiedPattern
    , simplifiedPredicate
    , simplifiedSubstitution
    , simplifiedTerm
    ) where

import Prelude.Kore

import Control.Comonad.Trans.Cofree
    ( CofreeF ((:<))
    )
import qualified Data.Functor.Foldable as Recursive

import Branch
    ( BranchT
    )
import qualified Kore.Attribute.Pattern as Attribute.Pattern
    ( fullySimplified
    , setSimplified
    )
import Kore.Internal.Condition
    ( Condition
    )
import Kore.Internal.Conditional
    ( Conditional (..)
    )
import qualified Kore.Internal.Conditional as Conditional.DoNotUse
import Kore.Internal.OrCondition
    ( OrCondition
    )
import Kore.Internal.OrPattern
    ( OrPattern
    )
import Kore.Internal.Pattern
    ( Pattern
    )
import qualified Kore.Internal.Pattern as Pattern
    ( splitTerm
    , withCondition
    )
import Kore.Internal.Predicate
    ( Predicate
    )
import Kore.Internal.Substitution
    ( Substitution
    )
import qualified Kore.Internal.Substitution as Substitution
import Kore.Internal.TermLike
    ( TermLike
    )
import Kore.Internal.Variable
    ( InternalVariable
    )
import Kore.Step.Simplification.Data
    ( Env (..)
    , Simplifier
    , SimplifierT
    )
import qualified Kore.Step.Simplification.Data as Kore
import SMT
    ( NoSMT
    )

import qualified Test.SMT as Test

runSimplifier :: Env Simplifier -> Simplifier a -> IO a
runSimplifier env = Test.runSMT . Kore.runSimplifier env

runSimplifierNoSMT :: Env (SimplifierT NoSMT) -> SimplifierT NoSMT a -> IO a
runSimplifierNoSMT env = Test.runNoSMT . Kore.runSimplifier env

runSimplifierBranch :: Env Simplifier -> BranchT Simplifier a -> IO [a]
runSimplifierBranch env = Test.runSMT . Kore.runSimplifierBranch env

simplifiedTerm :: TermLike variable -> TermLike variable
simplifiedTerm =
    Recursive.unfold (simplifiedWorker . Recursive.project)
  where
    simplifiedWorker (attrs :< patt) =
        Attribute.Pattern.setSimplified Attribute.Pattern.fullySimplified attrs
        :< patt

simplifiedPredicate :: Predicate variable -> Predicate variable
simplifiedPredicate = fmap simplifiedTerm

simplifiedSubstitution
    :: InternalVariable variable
    => Substitution variable
    -> Substitution variable
simplifiedSubstitution =
    Substitution.unsafeWrapFromAssignments
    . Substitution.unwrap
    . Substitution.mapTerms simplifiedTerm

simplifiedCondition
    :: InternalVariable variable
    => Condition variable
    -> Condition variable
simplifiedCondition conditional =
    Conditional
        { term = ()
        , predicate = simplifiedPredicate predicate
        , substitution = simplifiedSubstitution substitution
        }
    where
      predicate = Conditional.DoNotUse.predicate conditional
      substitution = Conditional.DoNotUse.substitution conditional

simplifiedPattern
    :: InternalVariable variable
    => Pattern variable
    -> Pattern variable
simplifiedPattern patt =
    simplifiedTerm term `Pattern.withCondition` simplifiedCondition condition
  where
    (term, condition) = Pattern.splitTerm patt

simplifiedOrPattern
    :: InternalVariable variable
    => OrPattern variable
    -> OrPattern variable
simplifiedOrPattern = fmap simplifiedPattern

simplifiedOrCondition
    :: InternalVariable variable
    => OrCondition variable
    -> OrCondition variable
simplifiedOrCondition = fmap simplifiedCondition
