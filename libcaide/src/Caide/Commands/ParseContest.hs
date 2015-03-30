{-# LANGUAGE OverloadedStrings #-}
module Caide.Commands.ParseContest(
      createContest
) where

import Data.List (find)
import qualified Data.Text as T

import Caide.Types

import Caide.Parsers.CodeforcesContest
import Caide.Parsers.CodeChefContest

createContest :: URL -> CaideIO ()
createContest contestUrl = case findContestParser contestUrl of
    Nothing -> throw . T.concat $ [contestUrl, " is not recognized as a supported contest URL"]
    Just contestParser -> contestParser `parseContest` contestUrl

contestParsers :: [ContestParser]
contestParsers = [codeforcesContestParser, codeChefContestParser]

findContestParser :: URL -> Maybe ContestParser
findContestParser url = find (`contestUrlMatches` url) contestParsers


