module Router exposing (EventSortBy(..), GameSortBy(..), Target(..), buildFromTarget, pageName, routeToTarget)

import Auth exposing (Cred)
import Dict
import TableSort exposing (Sorting)
import Url exposing (Url)
import Url.Builder exposing (absolute)
import Url.Parser exposing ((</>), (<?>), Parser, int, map, oneOf, parse, s, string, top)


type Target
    = Login
    | Landing
    | Profile
    | Events (Maybe (Sorting EventSortBy))
    | CreateEvent
    | EventEdit Int
    | EventShow Int (Maybe (Sorting GameSortBy))
    | CreateGame Int
    | EditGame Int Int
    | CredentialedArrival Target Cred
    | Register
    | CompleteRegistration String


type EventSortBy
    = EventName
    | Date
    | Location


eventSortToString : EventSortBy -> String
eventSortToString sort =
    case sort of
        EventName ->
            "name"

        Date ->
            "date"

        Location ->
            "loc"


eventSortDict : Dict.Dict String EventSortBy
eventSortDict =
    Dict.fromList
        [ ( "name", EventName )
        , ( "date", Date )
        , ( "loc", Location )
        ]


type GameSortBy
    = GameName
    | MinPlayers
    | MaxPlayers
    | Duration
    | Interest


gameSortToString : GameSortBy -> String
gameSortToString sort =
    case sort of
        GameName ->
            "name"

        MinPlayers ->
            "minplayer"

        MaxPlayers ->
            "maxplayer"

        Duration ->
            "dur"

        Interest ->
            "interest"


gameSortDict : Dict.Dict String GameSortBy
gameSortDict =
    Dict.fromList
        [ ( "name", GameName )
        , ( "minplayer", MinPlayers )
        , ( "maxplayer", MaxPlayers )
        , ( "dur", Duration )
        , ( "interest", Interest )
        ]



{- convert a path to a page route -}


routeToTarget : Url -> Maybe Target
routeToTarget url =
    Debug.log "route-to" (parse router (Debug.log "log-from" url))



{- render a path based on a page target -}


buildFromTarget : Target -> String
buildFromTarget target =
    case target of
        Landing ->
            absolute [] []

        Login ->
            absolute [ "login" ] []

        Profile ->
            absolute [ "profile" ] []

        Events sorting ->
            absolute [ "events" ] (TableSort.builder eventSortToString sorting)

        CreateEvent ->
            absolute [ "new_event" ] []

        EventEdit name ->
            absolute [ "event", String.fromInt name ] []

        EventShow id sorting ->
            absolute [ "games", String.fromInt id ] (TableSort.builder gameSortToString sorting)

        CreateGame event_id ->
            absolute [ "event", String.fromInt event_id, "create_game" ] []

        EditGame event_id game_id ->
            absolute [ "events", String.fromInt event_id, "game", String.fromInt game_id, "edit" ] []

        Register ->
            absolute [ "register" ] []

        CredentialedArrival _ _ ->
            absolute [ "handle_registration" ] []

        CompleteRegistration email ->
            absolute [ "complete_registration", email ] []



{- used to mark a CSS class for the page -}


pageName : Target -> String
pageName target =
    case target of
        Landing ->
            "landing"

        Login ->
            "login"

        Profile ->
            "profile"

        Events _ ->
            "events"

        CreateEvent ->
            "event"

        EventEdit _ ->
            "event"

        EventShow _ _ ->
            "games"

        CreateGame _ ->
            "game_create"

        EditGame _ _ ->
            "game_edit"

        Register ->
            "register"

        CredentialedArrival _ _ ->
            "mail-handling"

        CompleteRegistration _ ->
            "registration"


router : Parser (Target -> c) c
router =
    oneOf
        [ map Landing top
        , map Login (s "login")
        , map Profile (s "profile")
        , map Events (s "events" <?> TableSort.parser eventSortDict)
        , map CreateEvent (s "new_event")
        , map Register (s "register")
        , map CreateGame (s "event" </> int </> s "create_game")
        , map EventEdit (s "event" </> int)
        , map EventShow (s "games" </> int <?> TableSort.parser gameSortDict)
        , map EditGame (s "events" </> int </> s "game" </> int </> s "edit")
        , map registrationArrival (s "handle_registration" </> string </> Auth.fragmentParser)
        , map CompleteRegistration (s "complete_registration" </> string)
        ]


registrationArrival : String -> Cred -> Target
registrationArrival email cred =
    CredentialedArrival (CompleteRegistration email) cred
