module ViewUtil exposing (inputPair, maybeSubmit, svgIcon)

-- more like "EwwwwUtil" amirite?

import Html exposing (Attribute, Html, button, div, input, label, text)
import Html.Attributes exposing (class, disabled, for, id, type_, value)
import Html.Attributes.Extra exposing (attributeIf)
import Html.Events exposing (onInput)
import Svg exposing (svg, use)
import Svg.Attributes as SAttr


inputPair : List (Attribute msg) -> String -> String -> (String -> msg) -> Html msg
inputPair attrs name v event =
    let
        pid =
            String.toLower name
    in
    div [ class "field" ]
        [ label [ for pid ] [ text name ]
        , input ([ id pid, onInput event, value v ] ++ attrs) []
        ]


maybeSubmit : Bool -> String -> Html msg
maybeSubmit pred label =
    button [ type_ "submit", attributeIf (not pred) (disabled True) ] [ text label ]


svgIcon : String -> Html msg
svgIcon name =
    svg [ SAttr.class ("icon " ++ name) ]
        [ use [ SAttr.xlinkHref ("/assets/icons.svg#" ++ name) ] [] ]
