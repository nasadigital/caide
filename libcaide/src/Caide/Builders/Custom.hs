module Caide.Builders.Custom (
      builder
) where

import Filesystem.Path ((</>))
import Filesystem.Path.CurrentOS (decodeString, encodeString)

import System.Exit (ExitCode(..))
import System.Process (shell, createProcess, waitForProcess, cwd)

import Caide.Types

builder :: String -> CaideEnvironment -> String -> IO BuilderResult
builder name env probId = do
    cmd <- getUserOption env name "build_and_run_tests"
    evaluatesTests <- getUserOption env name "evaluates_tests"
    let caideRoot = getRootDirectory env
        probDir = caideRoot </> decodeString probId
        process = shell cmd

    putStrLn $ unlines ["Executing custom test runner: " ++ name, cmd]
    (_, _, _, ph) <- createProcess process { cwd = Just (encodeString probDir) }
    exitCode <- waitForProcess ph
    case exitCode of
        ExitSuccess -> do
            putStrLn "Done"
            return $ if evaluatesTests then TestsPassed else TestsNotRun
        ExitFailure code -> do
            putStrLn $ "Builder exit code " ++ show code
            return $ if evaluatesTests && code == 0xCA1DE then TestsFailed else BuildFailed

