{-# OPTIONS_GHC -Wno-unused-top-binds    #-}
-- Added for outputFileName

module Main (main) where

import Prelude.Kore

import Control.Concurrent.MVar
import Control.Monad.Trans
    ( lift
    )
import Control.Monad.Trans.Reader
    ( runReaderT
    )
import Data.Reflection
import Data.Semigroup
    ( (<>)
    )
import Options.Applicative
    ( InfoMod
    , Parser
    , argument
    , auto
    , flag
    , fullDesc
    , header
    , help
    , long
    , metavar
    , option
    , progDesc
    , readerError
    , short
    , str
    , strOption
    , value
    )
import System.Exit
    ( exitFailure
    )

import Data.Limit
    ( Limit (..)
    )
import Kore.Exec
    ( proveWithRepl
    )
import qualified Kore.IndexedModule.MetadataToolsBuilder as MetadataTools
    ( build
    )
import Kore.Log
    ( ActualEntry (..)
    , KoreLogOptions (..)
    , LogAction (..)
    , emptyLogger
    , getLoggerT
    , koreLogTransformer
    , swappableLogger
    , withLogger
    )
import Kore.Log.KoreLogOptions
    ( parseKoreLogOptions
    )
import Kore.Repl.Data
import Kore.Step.SMT.Lemma
import Kore.Syntax.Module
    ( ModuleName (..)
    )
import qualified SMT

import GlobalMain

-- | Represents a file name along with its module name passed.
data KoreModule = KoreModule
    { fileName   :: !FilePath
    , moduleName :: !ModuleName
    }

-- | SMT Timeout and (optionally) a custom prelude path.
data SmtOptions = SmtOptions
    { timeOut :: !SMT.TimeOut
    , prelude :: !(Maybe FilePath)
    }

-- | Options for the kore repl.
data KoreReplOptions = KoreReplOptions
    { definitionModule :: !KoreModule
    , proveOptions     :: !KoreProveOptions
    , smtOptions       :: !SmtOptions
    , replMode         :: !ReplMode
    , replScript       :: !ReplScript
    , outputFile       :: !OutputFile
    , koreLogOptions   :: !KoreLogOptions
    }

parseKoreReplOptions :: Parser KoreReplOptions
parseKoreReplOptions =
    KoreReplOptions
    <$> parseMainModule
    <*> parseKoreProveOptions
    <*> parseSmtOptions
    <*> parseReplMode
    <*> parseReplScript
    <*> parseOutputFile
    <*> parseKoreLogOptions (ExeName "kore-repl")
  where
    parseMainModule :: Parser KoreModule
    parseMainModule  =
        KoreModule
        <$> argument str
            (  metavar "MAIN_DEFINITION_FILE"
            <> help "Kore definition file to verify and use for execution"
            )
        <*> parseModuleName' "MAIN" "Kore main module name." "module"

    parseModuleName' :: String -> String -> String -> Parser ModuleName
    parseModuleName' name helpMessage longName =
        GlobalMain.parseModuleName
            (name <> "_MODULE")
            longName
            helpMessage

    parseSmtOptions :: Parser SmtOptions
    parseSmtOptions =
        SmtOptions
        <$> option readSMTTimeOut
            (  metavar "SMT_TIMEOUT"
            <> long "smt-timeout"
            <> help "Timeout for calls to the SMT solver, in miliseconds"
            <> value defaultTimeOut
            )
        <*> optional
            ( strOption
                (  metavar "SMT_PRELUDE"
                <> long "smt-prelude"
                <> help "Path to the SMT prelude file"
                )
            )

    parseReplMode :: Parser ReplMode
    parseReplMode =
        flag
            Interactive
            RunScript
            ( long "run-mode"
            <> short 'r'
            <> help "Repl run script mode"
            )

    parseReplScript :: Parser ReplScript
    parseReplScript =
        ReplScript
        <$> optional
            ( strOption
                ( metavar "REPL_SCRIPT"
                <> long "repl-script"
                <> help "Path to the repl script file"
                )
            )

    SMT.Config { timeOut = defaultTimeOut } = SMT.defaultConfig

    readSMTTimeOut = do
        i <- auto
        if i <= 0
            then readerError "smt-timeout must be a positive integer."
            else return $ SMT.TimeOut $ Limit i

    parseOutputFile :: Parser OutputFile
    parseOutputFile =
        OutputFile
        <$> optional
            (strOption
                (  metavar "PATTERN_OUTPUT_FILE"
                <> long "output"
                <> help "Output file to contain final Kore pattern."
                )
            )

parserInfoModifiers :: InfoMod options
parserInfoModifiers =
    fullDesc
    <> progDesc "REPL debugger for proofs"
    <> header "kore-repl - a repl for Kore proofs"

main :: IO ()
main = do
    options <-
        mainGlobal (ExeName "kore-repl") parseKoreReplOptions parserInfoModifiers
    case localOptions options of
        Nothing -> pure ()
        Just koreReplOptions -> mainWithOptions koreReplOptions

mainWithOptions :: KoreReplOptions -> IO ()
mainWithOptions
    KoreReplOptions
        { definitionModule
        , proveOptions
        , smtOptions
        , replScript
        , replMode
        , outputFile
        , koreLogOptions
        }
  = do
    mLogger <- newMVar $ koreLogTransformer koreLogOptions emptyLogger
    let initialLogger = swappableLogger mLogger
    flip runReaderT initialLogger . getLoggerT $ do
        definition <- loadDefinitions [definitionFileName, specFile]
        indexedModule <- loadModule mainModuleName definition
        specDefIndexedModule <- loadModule specModule definition

        let
            smtConfig =
                SMT.defaultConfig
                    { SMT.timeOut = smtTimeOut
                    , SMT.preludeFile = smtPrelude
                    }
        if replMode == RunScript && isNothing (unReplScript replScript)
            then lift $ do
                putStrLn
                    "You must supply the path to the repl script\
                    \ in order to run the repl in run-script mode."
                exitFailure
            else
                lift
                $ withLogger koreLogOptions
                    $ runSMT
                        smtConfig
                        initialLogger
                        $ do
                            give
                                (MetadataTools.build indexedModule)
                                (declareSMTLemmas indexedModule)
                            proveWithRepl
                                indexedModule
                                specDefIndexedModule
                                Nothing
                                mLogger
                                replScript
                                replMode
                                outputFile
                                mainModuleName

  where
    runSMT
        :: SMT.Config
        -> LogAction IO ActualEntry
        -> SMT.SMT ()
        -> ( LogAction IO ActualEntry -> IO () )
    runSMT smtConfig logger smt logAction =
        SMT.runSMT smtConfig (logger <> logAction) smt

    mainModuleName :: ModuleName
    mainModuleName = moduleName definitionModule

    definitionFileName :: FilePath
    definitionFileName = fileName definitionModule

    specModule :: ModuleName
    specModule = specMainModule proveOptions

    specFile :: FilePath
    specFile = specFileName proveOptions

    smtTimeOut :: SMT.TimeOut
    smtTimeOut = timeOut smtOptions

    smtPrelude :: Maybe FilePath
    smtPrelude = prelude smtOptions
