module Test.Kore.Step.Simplification.Forall
    ( test_forallSimplification
    ) where

import Prelude.Kore

import Test.Tasty

import Kore.Internal.OrPattern
    ( OrPattern
    )
import qualified Kore.Internal.OrPattern as OrPattern
import Kore.Internal.Pattern as Pattern
import Kore.Internal.Predicate
    ( makeAndPredicate
    , makeCeilPredicate_
    , makeEqualsPredicate_
    , makeForallPredicate
    , makeTruePredicate
    , makeTruePredicate_
    )
import qualified Kore.Internal.Substitution as Substitution
import Kore.Internal.TermLike
import qualified Kore.Step.Simplification.Forall as Forall
    ( makeEvaluate
    , simplify
    )
import Kore.Variables.UnifiedVariable
    ( UnifiedVariable (..)
    )

import qualified Test.Kore.Step.MockSymbols as Mock
import Test.Tasty.HUnit.Ext

test_forallSimplification :: [TestTree]
test_forallSimplification =
    [ testCase "Forall - or distribution"
        -- forall(a or b) = forall(a) or forall(b)
        (assertEqual ""
            (OrPattern.fromPatterns
                [ Conditional
                    { term = mkForall Mock.x something1OfX
                    , predicate = makeTruePredicate_
                    , substitution = mempty
                    }
                , Conditional
                    { term = mkForall Mock.x something2OfX
                    , predicate = makeTruePredicate_
                    , substitution = mempty
                    }
                ]
            )
            (evaluate
                (makeForall
                    Mock.x
                    [something1OfXExpanded, something2OfXExpanded]
                )
            )
        )
    , testCase "Forall - bool operations"
        (do
            -- forall(top) = top
            assertEqual "forall(top)"
                (OrPattern.fromPatterns
                    [ Pattern.top ]
                )
                (evaluate
                    (makeForall
                        Mock.x
                        [Pattern.top]
                    )
                )
            -- forall(bottom) = bottom
            assertEqual "forall(bottom)"
                (OrPattern.fromPatterns
                    []
                )
                (evaluate
                    (makeForall
                        Mock.x
                        []
                    )
                )
        )
    , testCase "expanded Forall - bool operations"
        (do
            -- forall(top) = top
            assertEqual "forall(top)"
                Pattern.top
                (makeEvaluate
                    Mock.x
                    (Pattern.top :: Pattern Variable)
                )
            -- forall(bottom) = bottom
            assertEqual "forall(bottom)"
                Pattern.bottom
                (makeEvaluate
                    Mock.x
                    (Pattern.bottom :: Pattern Variable)
                )
        )
    , testCase "forall applies substitution if possible"
        -- forall x . (t(x) and p(x) and [x = alpha, others])
        (assertEqual "forall with substitution"
            Conditional
                { term =
                    mkForall Mock.x
                        (mkAnd
                            (mkAnd
                                (Mock.f $ mkElemVar Mock.x)
                                (mkCeil_ (Mock.h (mkElemVar Mock.x)))
                            )
                            (mkAnd
                                (mkEquals_ (mkElemVar Mock.x) gOfA)
                                (mkEquals_ (mkElemVar Mock.y) fOfA)
                            )
                        )
                , predicate = makeTruePredicate Mock.testSort
                , substitution = mempty
                }
            (makeEvaluate
                Mock.x
                Conditional
                    { term = Mock.f $ mkElemVar Mock.x
                    , predicate = makeCeilPredicate_ (Mock.h (mkElemVar Mock.x))
                    , substitution =
                        Substitution.wrap
                        $ Substitution.mkUnwrappedSubstitution
                            [(ElemVar Mock.x, gOfA), (ElemVar Mock.y, fOfA)]
                    }
            )
        )
    , testCase "forall disappears if variable not used"
        -- forall x . (t and p and s)
        (assertEqual "forall with substitution"
            Conditional
                { term = fOfA
                , predicate = makeCeilPredicate_ gOfA
                , substitution = mempty
                }
            (makeEvaluate
                Mock.x
                Conditional
                    { term = fOfA
                    , predicate = makeCeilPredicate_ gOfA
                    , substitution = mempty
                    }
            )
        )
    , testCase "forall applied when term contains variable, non-bool predicate"
        -- forall x . (t(x) and p and s)
        (assertEqual "forall on term"
            Conditional
                { term = mkForall Mock.x (mkAnd fOfX (mkCeil_ gOfA))
                , predicate = makeTruePredicate Mock.testSort
                , substitution = mempty
                }
            (makeEvaluate
                Mock.x
                Conditional
                    { term = fOfX
                    , predicate = makeCeilPredicate_ gOfA
                    , substitution = mempty
                    }
            )
        )
    , testCase "forall applied when term contains variable, bool predicate"
        -- forall x . (t(x) and top and top)
        (assertEqual "forall on term bool predicate"
            Conditional
                { term = mkForall Mock.x fOfX
                , predicate = makeTruePredicate_
                , substitution = mempty
                }
            (makeEvaluate
                Mock.x
                Conditional
                    { term = fOfX
                    , predicate = makeTruePredicate_
                    , substitution = mempty
                    }
            )
        )
    , testCase "forall applied when predicate contains variable, non-bool term"
        -- forall x . (t and p(x) and s)
        --    = (forall x . (t and p(x) and s)
        (assertEqual "forall on predicate"
            Conditional
                { term = mkForall Mock.x
                    (mkAnd
                        (mkAnd
                            fOfA
                            (mkCeil_ fOfX)
                        )
                        (mkEquals_ (mkElemVar Mock.y) fOfA)
                    )
                , predicate = makeTruePredicate Mock.testSort
                , substitution = mempty
                }
            (makeEvaluate
                Mock.x
                Conditional
                    { term = fOfA
                    , predicate = makeCeilPredicate_ fOfX
                    , substitution =
                        Substitution.wrap
                        $ Substitution.mkUnwrappedSubstitution
                        [(ElemVar Mock.y, fOfA)]
                    }
            )
        )
    , testCase "forall applied when predicate contains variable, bool term"
        -- forall x . (top and p(x) and s)
        --    = top and (forall x . p(x) and s)
        (assertEqual "forall on predicate"
            Conditional
                { term = mkTop_
                , predicate = makeForallPredicate Mock.x
                    (makeAndPredicate
                        (makeCeilPredicate_ fOfX)
                        (makeEqualsPredicate_ (mkElemVar Mock.y) fOfA)
                    )
                , substitution = mempty
                }
            (makeEvaluate
                Mock.x
                Conditional
                    { term = mkTop_
                    , predicate = makeCeilPredicate_ fOfX
                    , substitution =
                        Substitution.wrap
                        $ Substitution.mkUnwrappedSubstitution
                        [(ElemVar Mock.y, fOfA)]
                    }
            )
        )
    , testCase "forall moves substitution above"
        -- forall x . (t(x) and p(x) and s)
        (assertEqual "forall moves substitution"
            Conditional
                { term =
                    mkForall Mock.x
                        (mkAnd
                            (mkAnd fOfX (mkEquals_ fOfX gOfA))
                            (mkEquals_ (mkElemVar Mock.y) hOfA)
                        )
                , predicate = makeTruePredicate Mock.testSort
                , substitution = mempty
                }
            (makeEvaluate
                Mock.x
                Conditional
                    { term = fOfX
                    , predicate = makeEqualsPredicate_ fOfX gOfA
                    , substitution =
                        Substitution.wrap
                        $ Substitution.mkUnwrappedSubstitution
                        [(ElemVar Mock.y, hOfA)]
                    }
            )
        )
    {-
    Uncomment this if we ever decide to substitute + reevaluate in foralls
    , testCase "forall reevaluates"
        -- forall x . (top and (f(x) = f(g(a)) and [x=g(a)])
        --    = top.s
        (assertEqual "forall reevaluates"
            Pattern.top
            (makeEvaluate
                Mock.x
                Pattern
                    { term = mkTop_
                    , predicate = makeEqualsPredicate_ fOfX (Mock.f gOfA)
                    , substitution = [(Mock.x, gOfA)]
                    }
            )
        )
        -}
    ]
  where
    fOfA = Mock.f Mock.a
    fOfX = Mock.f (mkElemVar Mock.x)
    gOfA = Mock.g Mock.a
    hOfA = Mock.h Mock.a
    something1OfX = Mock.plain10 (mkElemVar Mock.x)
    something2OfX = Mock.plain11 (mkElemVar Mock.x)
    something1OfXExpanded = Conditional
        { term = something1OfX
        , predicate = makeTruePredicate_
        , substitution = mempty
        }
    something2OfXExpanded = Conditional
        { term = something2OfX
        , predicate = makeTruePredicate_
        , substitution = mempty
        }

makeForall
    :: InternalVariable variable
    => ElementVariable variable
    -> [Pattern variable]
    -> Forall Sort variable (OrPattern variable)
makeForall variable patterns =
    Forall
        { forallSort = testSort
        , forallVariable  = variable
        , forallChild       = OrPattern.fromPatterns patterns
        }

testSort :: Sort
testSort = Mock.testSort

evaluate :: Forall Sort Variable (OrPattern Variable) -> OrPattern Variable
evaluate = Forall.simplify

makeEvaluate :: ElementVariable Variable -> Pattern Variable -> Pattern Variable
makeEvaluate = Forall.makeEvaluate
