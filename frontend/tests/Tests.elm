module Tests exposing (..)

import Test exposing (Test, describe, test)
import Expect

import Url exposing (Url)

import Router exposing (..)

pickARoute : Router.Target -> Int
pickARoute tgt =
  case tgt of
    Router.Landing -> 0
    Router.Login -> 1
    Router.Profile -> 2
    Router.Events -> 3
    Router.CreateEvent -> 4
    Router.EventEdit _ -> 5
    -- remember to update the Routing suite if you add targets

suite : Test
suite =
  describe "Routing"
    [ routePair "Landing" "/" Landing
    , routePair "Login" "/login" Login
    , routePair "Profile" "/profile" Profile
    , routePair "Events" "/events" Events
    , routePair "EventEdit 16" "/event/16" (EventEdit "16")
    , routePair "CreateEvent" "/new_event" CreateEvent
    ]


routePair : String  -> String-> Target -> Test
routePair targetName path target  =
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
