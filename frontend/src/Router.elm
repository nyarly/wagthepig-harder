module Router exposing (Target(..), routeToTarget, buildFromTarget, pageName)

import Url exposing (Url)
import Url.Parser exposing (Parser, map, parse, s, top, oneOf)
import Url.Builder exposing (absolute)

type Target
  = Login
  | Landing
  | Profile

router : Parser (Target -> c) c
router =
  oneOf
    [ map Landing top
    , map Login ( s "login" )
    , map Profile ( s "profile" )
    ]

builder : Target -> String
builder target =
  case target of
    Landing -> absolute [] []
    Login -> absolute ["login"] []
    Profile -> absolute ["profile"] []

routeToTarget : Url -> Maybe Target
routeToTarget url =
  parse router url

buildFromTarget : Target -> String
buildFromTarget target =
  builder target

pageName : Target -> String
pageName target =
  case target of
    Landing -> "landing"
    Login -> "login"
    Profile -> "profile"
