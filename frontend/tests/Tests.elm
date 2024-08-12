module Tests exposing (..)

import Test exposing (Test, describe, test)
import Expect

import Url exposing (Url)

import Router exposing (..)

suite : Test
suite =
  describe "Routing"
    [ routePair "/" Landing "Landing"
    , routePair "/login" Login "Login"
    ]


routePair : String -> Target -> String -> Test
routePair path target targetName =
  let
    url = Url Url.Http "" Nothing path Nothing Nothing
  in
    describe (path ++ " <-> " ++ targetName)
      [ test ("routes " ++ path ++ " to " ++ targetName) <|
        \_ ->
            Expect.equal (Router.routeToTarget url) (Just target)
      , test ("builds "++ path ++" from "++ targetName) <|
        \_ ->
            Expect.equal (Router.buildFromTarget target) path
      ]
