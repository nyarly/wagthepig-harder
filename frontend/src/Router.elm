module Router exposing  (Target(..), routeToTarget, buildFromTarget, pageName)

import Url exposing (Url)
import Url.Parser exposing (Parser, map, parse, s, top, oneOf, (</>), string)
import Url.Builder exposing (absolute)
import Auth exposing (Cred)

type Target
  = Login
  | Landing
  | Profile
  | Events
  | CreateEvent
  | EventEdit String
  | CredentialedArrival Target Cred
  | CompleteRegistration String

routeToTarget : Url -> Maybe Target
routeToTarget url =
  parse router url

buildFromTarget : Target -> String
buildFromTarget target =
  case target of
    Landing -> absolute [] []
    Login -> absolute ["login"] []
    Profile -> absolute ["profile"] []
    Events -> absolute ["events"] []
    CreateEvent -> absolute ["new_event"] []
    EventEdit name -> absolute ["event", name] []
    CredentialedArrival _ _ -> absolute ["handle_registration"] []
    CompleteRegistration email -> absolute [ "complete_registration", email ] []

{- used to mark a CSS class for the page -}
pageName : Target -> String
pageName target =
  case target of
    Landing -> "landing"
    Login -> "login"
    Profile -> "profile"
    Events -> "events"
    CreateEvent -> "event"
    EventEdit _ -> "event"
    CredentialedArrival _ _ -> "mail-handling"
    CompleteRegistration _ -> "registration"

router : Parser (Target -> c) c
router =
  oneOf
    [ map Landing top
    , map Login ( s "login" )
    , map Profile ( s "profile" )
    , map Events ( s "events" )
    , map CreateEvent ( s "new_event" )
    , map EventEdit ( s "event" </> string )
    , map registrationArrival ( s "handle_registration" </> string </> Auth.fragmentParser )
    , map CompleteRegistration ( s "complete_registration" </> string )
    ]

registrationArrival : String -> Cred -> Target
registrationArrival email cred =
  CredentialedArrival (CompleteRegistration email) cred
