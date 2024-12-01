module Router exposing (Target(..), buildFromTarget, pageName, routeToTarget)

import Auth exposing (Cred)
import Url exposing (Url)
import Url.Builder exposing (absolute)
import Url.Parser exposing ((</>), Parser, int, map, oneOf, parse, s, string, top)


type Target
    = Login
    | Landing
    | Profile
    | Events
    | CreateEvent
    | EventEdit Int
    | CredentialedArrival Target Cred
    | Register
    | CompleteRegistration String


routeToTarget : Url -> Maybe Target
routeToTarget url =
    Debug.log "route-to" (parse router (Debug.log "log-from" url))


buildFromTarget : Target -> String
buildFromTarget target =
    case target of
        Landing ->
            absolute [] []

        Login ->
            absolute [ "login" ] []

        Profile ->
            absolute [ "profile" ] []

        Events ->
            absolute [ "events" ] []

        CreateEvent ->
            absolute [ "new_event" ] []

        EventEdit name ->
            absolute [ "event", String.fromInt name ] []

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

        Events ->
            "events"

        CreateEvent ->
            "event"

        EventEdit _ ->
            "event"

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
        , map Events (s "events")
        , map CreateEvent (s "new_event")
        , map Register (s "register")
        , map EventEdit (s "event" </> int)
        , map registrationArrival (s "handle_registration" </> string </> Auth.fragmentParser)
        , map CompleteRegistration (s "complete_registration" </> string)
        ]


registrationArrival : String -> Cred -> Target
registrationArrival email cred =
    CredentialedArrival (CompleteRegistration email) cred
