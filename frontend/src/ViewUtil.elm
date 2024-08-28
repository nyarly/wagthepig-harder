module ViewUtil exposing (inputPair)
-- more like "EwwwwUtil" amirite?

import Html exposing (Html, Attribute, div, form, input, label, text)
import Html.Attributes exposing (for, id, value, class)
import Html.Events exposing (onInput)

inputPair : List (Attribute msg) -> String -> String -> (String -> msg) -> Html msg
inputPair attrs name v event =
  let
      pid = String.toLower name
  in
    div [ class "field" ]
    [ label [ for pid ] [ text name ]
    , input ([ id pid, onInput event, value v ] ++ attrs) []
    ]
