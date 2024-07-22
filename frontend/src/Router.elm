module Router exposing (routeTarget, Target)

import Url
import Url.Parser exposing (Parser, parse, s, top, oneOf)

type Target
  = Login
  | Landing

routeTarget : Url -> Target
route url =
