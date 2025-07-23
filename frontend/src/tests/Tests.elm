module Tests exposing (pickARoute, routePair, suite)

import Expect
import Router exposing (..)
import Test exposing (Test, describe, test)
import Url exposing (Url)


pickARoute : Router.Target -> Int
pickARoute tgt =
    case tgt of
        Router.CredentialedArrival _ _ ->
            -1

        Router.Landing ->
            0

        Router.Login ->
            1

        Router.Profile ->
            2

        Router.Events _ ->
            3

        Router.CreateEvent ->
            4

        Router.EventEdit _ ->
            5

        Router.Register ->
            6

        Router.CompleteRegistration _ ->
            7



-- remember to update the Routing suite if you add targets


suite : Test
suite =
    describe "Routing"
        [ routePair "Landing" "/" Landing
        , routePair "Login" "/login" Login
        , routePair "Profile" "/profile" Profile
        , routePair "Events" "/events" (Events Nothing)
        , routePair "EventEdit 16" "/event/16" (EventEdit 16)
        , routePair "CreateEvent" "/new_event" CreateEvent
        , routePair "Register" "/register" Register
        , routePair "CompleteRegistration" "/complete_registration/test@example.com" (CompleteRegistration "test@example.com")
        ]



-- Because this handles creds, consider how to handle this elsewhere.
--  routePair "CredentialedArrival" "/handle_registration/test@example.com#TOKEN" (CredentialedArrival Cred.unauthenticated "test@example.com")


routePair : String -> String -> Target -> Test
routePair targetName path target =
    let
        url =
            Url Url.Http "" Nothing path Nothing Nothing
    in
    describe (path ++ " <-> " ++ targetName)
        [ test ("routes " ++ path ++ " to " ++ targetName) <|
            \_ ->
                Expect.equal (Router.routeToTarget url) (Just target)
        , test ("builds " ++ path ++ " from " ++ targetName) <|
            \_ ->
                Expect.equal (Router.buildFromTarget target) path
        ]
