--{-# LANGUAGE FlexibleContexts, Rank2Types #-}
{-# LANGUAGE OverloadedStrings #-}

module Caide.Configuration (
      -- * General utilities
      setProperties
    , orDefault
    , describeError

      -- * Caide configuration
    , readCaideConf
    , readCaideState
    , writeCaideConf
    , writeCaideState
    , defaultCaideConf
    , defaultCaideState

      -- * Caide options and state
    , getActiveProblem
    , setActiveProblem
    , getDefaultLanguage
    , getBuilder
    , getFeatures

      -- * Problem configuration
    , getProblemConfigFile
    , readProblemConfig
    , getProblemStateFile
    , readProblemState
    , defaultProblemConfig
    , defaultProblemState

) where

import Prelude hiding (readFile, FilePath)

import Control.Monad (forM_)
import Control.Monad.Except (catchError)
import Control.Monad.Trans (liftIO)
import Data.ConfigFile (ConfigParser, CPError, CPErrorData(OtherProblem), SectionSpec, OptionSpec,
                        set, emptyCP, add_section)
import Data.List (intercalate, isPrefixOf)
import Data.Text (Text)
import qualified Data.Text as T
import Filesystem (isDirectory)
import Filesystem.Path.CurrentOS (encodeString, fromText)
import Filesystem.Path (FilePath, (</>))

import System.Info (arch, os)

import Caide.Types
import Caide.Util (forceEither)


setProperties :: Monad m => ConfigFileHandle -> [(String, String, Text)] -> CaideM m ()
setProperties handle properties = forM_ properties $ \(section, key, value) ->
    setProp handle section key value

orDefault :: Monad m => CaideM m a -> a -> CaideM m a
orDefault getter defaultValue = getter `catchError` const (return defaultValue)

describeError :: CPError -> String
describeError (OtherProblem err, _) = err
describeError e                     = "Config parser error: " ++ show e

{--------------------------- Problem specific state ----------------------------}

getProblemStateFile :: Monad m => ProblemID -> CaideM m FilePath
getProblemStateFile probId = do
    root <- caideRoot
    return $ root </> fromText probId </> ".caideproblem" </> "config"

readProblemState :: ProblemID -> CaideIO ConfigFileHandle
readProblemState probId = do
    root <- caideRoot
    problemExists <- liftIO $ isDirectory $ root </> fromText probId </> ".caideproblem"
    if problemExists
    then getProblemStateFile probId >>= readConf
    else throw "No such problem"

getProblemConfigFile :: Monad m => ProblemID -> CaideM m FilePath
getProblemConfigFile probId = do
    root <- caideRoot
    return $ root </> fromText probId </> "problem.ini"

readProblemConfig :: ProblemID -> CaideIO ConfigFileHandle
readProblemConfig probId = do
    root <- caideRoot
    problemExists <- liftIO $ isDirectory $ root </> fromText probId </> ".caideproblem"
    if problemExists
    then getProblemConfigFile probId >>= readConf
    else throw "No such problem"


{--------------------------- Global options and state ----------------------------}
caideConfFile :: Monad m => CaideM m FilePath
caideConfFile = do
    root <- caideRoot
    return $ root </> "caide.ini"

caideStateFile :: Monad m => CaideM m FilePath
caideStateFile = do
    root <- caideRoot
    return $ root </> ".caide" </> "config"

readCaideConf :: CaideIO ConfigFileHandle
readCaideConf = caideConfFile >>= readConf

readCaideState :: CaideIO ConfigFileHandle
readCaideState = caideStateFile >>= readConf

writeCaideConf :: Monad m => ConfigParser -> CaideM m ConfigFileHandle
writeCaideConf cp = do
    filePath <- caideConfFile
    createConf filePath cp

writeCaideState :: Monad m => ConfigParser -> CaideM m ConfigFileHandle
writeCaideState cp = do
    filePath <- caideStateFile
    createConf filePath cp

getActiveProblem :: CaideIO ProblemID
getActiveProblem = do
    h <- readCaideState
    res <- getProp h "core" "problem" `orDefault` ""
    if T.null res
    then throw "No active problem. Switch to an existing problem with `caide checkout <problemID>`"
    else return res

setActiveProblem :: ProblemID -> CaideIO ()
setActiveProblem probId = do
    h <- readCaideState
    setProp h "core" "problem" probId

getBuilder :: CaideIO Text
getBuilder = do
    h <- readCaideConf
    getProp h "core" "builder"

getDefaultLanguage :: CaideIO Text
getDefaultLanguage = do
    h <- readCaideConf
    getProp h "core" "language"

getFeatures :: CaideIO [Text]
getFeatures = do
    h <- readCaideConf
    getProp h "core" "features"

{--------------------------- Internals -----------------------------}

addSection :: SectionSpec -> ConfigParser -> Either CPError ConfigParser
addSection section conf = add_section conf section

setValue :: SectionSpec -> OptionSpec -> String -> ConfigParser -> Either CPError ConfigParser
setValue section key value conf = set conf section key value

defaultCaideConf :: FilePath -> Bool -> ConfigParser
defaultCaideConf root useSystemHeaders = forceEither $
    addSection "core" emptyCP >>=
    setValue "core" "language" "cpp" >>=
    setValue "core" "features" "" >>=
    setValue "core" "builder" "none" >>=
    addSection "cpp" >>=
    setValue "cpp" "clang_options" (intercalate ",\n  " $ clangOptions root useSystemHeaders)

clangOptions :: FilePath -> Bool -> [String]
clangOptions root False = [
    "-target",
    "i386-pc-mingw32",
    "-nostdinc",
    "-isystem",
    encodeString $ root </> "include" </> "mingw-4.8.1",
    "-isystem",
    encodeString $ root </> "include" </> "mingw-4.8.1" </> "c++",
    "-isystem",
    encodeString $ root </> "include" </> "mingw-4.8.1" </> "c++" </> "mingw32",
    "-isystem",
    encodeString $ root </> "include",
    "-I",
    encodeString $ root </> "cpplib",
    "-std=c++11",
    "-D__MSVCRT__=1",
    "_D__declspec="
    ]

clangOptions root True | "mingw" `isPrefixOf` os = [
    "-target",
    "i386-pc-windows-msvc",
    "-I",
    encodeString $ root </> "cpplib"
    ]

clangOptions root True = [
    "-target",
    arch ++ "-" ++ os,
    "-isystem",
    encodeString $ root </> "include",
    "-I",
    encodeString $ root </> "cpplib"
    ]


defaultCaideState :: ConfigParser
defaultCaideState = forceEither $
    addSection "core" emptyCP >>=
    setValue "core" "problem" ""

defaultProblemConfig :: ConfigParser
defaultProblemConfig = forceEither $
    addSection "problem" emptyCP >>=
    setValue "problem" "double_precision" "0.000001"

defaultProblemState :: ConfigParser
defaultProblemState = forceEither $
    addSection "problem" emptyCP >>=
    setValue "problem" "language" "simplecpp"

