module ViewUtil exposing (inputPair, maybeSubmit)
-- more like "EwwwwUtil" amirite?

import Html exposing (Html, Attribute, div, input, label, text, button)
import Html.Events exposing (onInput)
import Html.Attributes exposing (for, id, value, class, disabled, type_)
import Html.Attributes.Extra exposing (attributeIf)

inputPair : List (Attribute msg) -> String -> String -> (String -> msg) -> Html msg
inputPair attrs name v event =
  let
      pid = String.toLower name
  in
    div [ class "field" ]
    [ label [ for pid ] [ text name ]
    , input ([ id pid, onInput event, value v ] ++ attrs) []
    ]

maybeSubmit : Bool -> String -> Html msg
maybeSubmit pred label =
  button [type_ "submit", attributeIf (not pred) (disabled True) ] [ text label ]
