module Tests exposing (routePair, suite)

import Expect
import Router exposing (..)
import String exposing (fromInt)
import TableSort exposing (SortOrder(..))
import Test exposing (Test, describe, test)
import Url exposing (Url)
import Url.Builder


testedRouteTargets : List Target
testedRouteTargets =
    let
        lister : List Target -> List Target
        lister list =
            case list of
                [] ->
                    lister (Landing :: list)

                Landing :: _ ->
                    lister (CompleteRegistration "blah blah" :: list)

                (CompleteRegistration _) :: _ ->
                    lister (CreateEvent :: list)

                CreateEvent :: _ ->
                    lister (CreateGame 1 :: list)

                (CreateGame _) :: _ ->
                    lister (EditGame 1 1 :: list)

                (EditGame _ _) :: _ ->
                    lister (EventEdit 1 :: list)

                (EventEdit _) :: _ ->
                    lister (EventShow 1 Nothing :: list)

                (EventShow _ _) :: _ ->
                    lister (Events Nothing :: list)

                (Events _) :: _ ->
                    lister (Login :: list)

                Login :: _ ->
                    lister (Profile :: list)

                Profile :: _ ->
                    lister (Register :: list)

                Register :: _ ->
                    lister (WhatShouldWePlay 1 Nothing :: list)

                (WhatShouldWePlay _ _) :: _ ->
                    list

                (CredentialedArrival _ _) :: _ ->
                    Debug.todo "very tricky to test"
    in
    lister []


allEventSortBy : List EventSortBy
allEventSortBy =
    [ EventName
    , Date
    , Location
    ]


eventSortArgs : EventSortBy -> ( Target, String, String )
eventSortArgs sort =
    case sort of
        EventName ->
            ( Events (Just ( sort, Ascending )), "Events by name", "/events?table_sort=name&table_order=ascd" )

        Date ->
            ( Events (Just ( sort, Ascending )), "Events by date", "/events?table_sort=date&table_order=ascd" )

        Location ->
            ( Events (Just ( sort, Ascending )), "Events by location", "/events?table_sort=loc&table_order=ascd" )

allReccoSortBy : List ReccoSortBy
allReccoSortBy =
    [ Length, Players, PresentInterested, PresentTeachers, ReccoName ]

reccoSortArgs : ReccoSortBy -> ( Target, String, String )
reccoSortArgs sort =
  case sort of
    Length ->
      ( WhatShouldWePlay 1 (Just ( sort, Ascending )), "Reccs by length", "/whatshouldweplay/1?table_sort=length&table_order=ascd" )
    Players ->
      ( WhatShouldWePlay 1 (Just ( sort, Ascending )), "Reccs by players", "/whatshouldweplay/1?table_sort=player&table_order=ascd" )
    PresentInterested ->
      ( WhatShouldWePlay 1 (Just ( sort, Ascending )), "Reccs by interested", "/whatshouldweplay/1?table_sort=interest&table_order=ascd" )
    PresentTeachers ->
      ( WhatShouldWePlay 1 (Just ( sort, Ascending )), "Reccs by teachers", "/whatshouldweplay/1?table_sort=teachers&table_order=ascd" )
    ReccoName ->
      ( WhatShouldWePlay 1 (Just ( sort, Ascending )), "Reccs by name", "/whatshouldweplay/1?table_sort=name&table_order=ascd" )


allGameSortBy : List GameSortBy
allGameSortBy =
    [ Duration, GameName, Interest, InterestCount, MaxPlayers, MinPlayers, TeacherCount ]


gameSortArgs : GameSortBy -> ( Target, String, String )
gameSortArgs sort =
  case sort of
    Duration ->
      ( EventShow 1 (Just ( sort, Ascending )), "Games by duration", "/games/1?table_sort=dur&table_order=ascd" )

    GameName ->
      ( EventShow 1 (Just ( sort, Ascending )), "Games by name", "/games/1?table_sort=name&table_order=ascd" )

    Interest ->
      ( EventShow 1 (Just ( sort, Ascending )), "Games by interest", "/games/1?table_sort=interest&table_order=ascd" )

    InterestCount ->
      ( EventShow 1 (Just ( sort, Ascending )), "Games by interested", "/games/1?table_sort=numinterest&table_order=ascd" )

    MaxPlayers ->
      ( EventShow 1 (Just ( sort, Ascending )), "Games by max", "/games/1?table_sort=maxplayer&table_order=ascd" )

    MinPlayers ->
      ( EventShow 1 (Just ( sort, Ascending )), "Games by min", "/games/1?table_sort=minplayer&table_order=ascd" )

    TeacherCount ->
      ( EventShow 1 (Just ( sort, Ascending )), "Games by teachers", "/games/1?table_sort=numteacher&table_order=ascd" )

suite : Test
suite =
    describe "Routing"
        (List.map routePair
            ([ ( Events Nothing, "Events Nothing", "/events" )
             , ( Events (Just ( EventName, Descending )), "Events name,desc", "/events?table_sort=name&table_order=desc" )
             ]
                ++ List.map
                    defaultRoutePairArgs
                    testedRouteTargets
                ++ List.map eventSortArgs allEventSortBy
                ++ List.map reccoSortArgs allReccoSortBy
                ++ List.map gameSortArgs allGameSortBy
            )
        )


defaultRoutePairArgs : Target -> ( Target, String, String )
defaultRoutePairArgs target =
    let
        q : (a -> String) -> ( a, TableSort.SortOrder ) -> String
        q s2s sort =
            Url.Builder.toQuery (TableSort.builder s2s (Just sort))

        ( name, path ) =
            case target of
                Router.Landing ->
                    ( "Landing", "/" )

                Router.Login ->
                    ( "Login", "/login" )

                Profile ->
                    ( "Profile", "/profile" )

                Events (Just sort) ->
                    ( "Events", "/events/" ++ q eventSortToString sort )

                Events Nothing ->
                    ( "Events", "/events" )

                CreateEvent ->
                    ( "CreateEvent", "/new_event" )

                EventEdit nick ->
                    ( "EventEdit", "/event/" ++ fromInt nick )

                EventShow nick (Just sort) ->
                    ( "EventShow", "/games/" ++ fromInt nick ++ q gameSortToString sort )

                EventShow nick Nothing ->
                    ( "EventShow", "/games/" ++ fromInt nick )

                WhatShouldWePlay nick Nothing ->
                    ( "WhatShouldWePlay", "/whatshouldweplay/" ++ fromInt nick )

                WhatShouldWePlay nick (Just sort) ->
                    ( "WhatShouldWePlay", "/whatshouldweplay/" ++ fromInt nick ++ q reccoSortToString sort )

                CreateGame ev ->
                    ( "CreateGame", "/event/" ++ fromInt ev ++ "/create_game" )

                EditGame ev id ->
                    ( "EditGame", "/events/" ++ fromInt ev ++ "/game/" ++ fromInt id ++ "/edit" )

                CredentialedArrival _ _ ->
                    ( "CredentialedArrival", "/credentialedarrival" )

                Register ->
                    ( "Register", "/register" )

                CompleteRegistration string ->
                    ( "CompleteRegistration", "/complete_registration/" ++ string )
    in
    ( target, name, path )


routePair : ( Target, String, String ) -> Test
routePair ( target, targetName, path ) =
    let
        defaultUrl : Url
        defaultUrl =
            Url Url.Http "" Nothing "broken!" Nothing Nothing

        url : Url
        url =
            Maybe.withDefault defaultUrl (Url.fromString ("http://example.com" ++ path))

        -- Url Url.Http "" Nothing path Nothing Nothing
    in
    describe (path ++ " <-> " ++ targetName)
        [ test ("routes " ++ path ++ " to " ++ targetName) <|
            \_ ->
                Expect.equal (Router.routeToTarget url) (Just target)
        , test ("builds " ++ path ++ " from " ++ targetName) <|
            \_ ->
                Expect.equal (Router.buildFromTarget target) path
        ]
