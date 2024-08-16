module Router exposing (Target(..), routeToTarget, buildFromTarget, pageName)

import Url exposing (Url)
import Url.Parser exposing (Parser, map, parse, s, top, oneOf)
import Url.Builder exposing (absolute)

type Target
  = Login
  | Landing
  | Profile
  | Events

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

pageName : Target -> String
pageName target =
  case target of
    Landing -> "landing"
    Login -> "login"
    Profile -> "profile"
    Events -> "events"

router : Parser (Target -> c) c
router =
  oneOf
    [ map Landing top
    , map Login ( s "login" )
    , map Profile ( s "profile" )
    , map Events ( s "events" )
    ]
