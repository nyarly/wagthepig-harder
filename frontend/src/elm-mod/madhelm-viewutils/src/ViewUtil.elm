module ViewUtil exposing (bareInputPair, checkbox, disabledIf, disabledMaybe, inputPair, maybeSubmit, onSelection, svgIcon)

-- more like "EwwwwUtil" amirite?

import Html exposing (Attribute, Html, button, div, input, label, text)
import Html.Attributes exposing (checked, class, disabled, for, id, type_, value)
import Html.Attributes.Extra as Extra exposing (attributeIf)
import Html.Events exposing (onCheck, onInput)
import Json.Decode as D
import Svg exposing (svg, use)
import Svg.Attributes as SAttr exposing (viewBox)


inputPair : List (Attribute msg) -> String -> String -> (String -> msg) -> Html msg
inputPair attrs name v event =
    div [ class "field" ] (bareInputPair attrs name v event)


bareInputPair : List (Attribute msg) -> String -> String -> (String -> msg) -> List (Html msg)
bareInputPair attrs name v event =
    let
        pid =
            String.toLower name
    in
    [ label [ for pid ] [ text name ]
    , input ([ id pid, onInput event, value v ] ++ attrs) []
    ]


checkbox : List (Attribute msg) -> String -> Bool -> (Bool -> msg) -> Html msg
checkbox attrs name tf event =
    let
        pid =
            String.toLower name
    in
    div [ class "field" ]
        [ input ([ type_ "checkbox", id pid, onCheck event, checked tf ] ++ attrs) []
        , label [ for pid ] [ text name ]
        ]


maybeSubmit : Bool -> String -> Html msg
maybeSubmit pred label =
    button [ type_ "submit", attributeIf (not pred) (disabled True) ] [ text label ]


disabledIf : Bool -> Attribute msg
disabledIf cond =
    if cond then
        disabled True

    else
        Extra.empty


disabledMaybe : Maybe a -> Attribute msg
disabledMaybe maybe =
    case maybe of
        Just _ ->
            Extra.empty

        Nothing ->
            disabled True


svgIcon : String -> Html msg
svgIcon name =
    svg [ SAttr.class ("icon " ++ name), viewBox "0 0 32 32" ]
        [ use [ SAttr.xlinkHref ("/assets/icons.svg#" ++ name) ] [] ]


onSelection : (List String -> msg) -> Attribute msg
onSelection msg =
    Html.Events.on "change" (D.map msg targetSelectedOptions)


targetSelectedOptions : D.Decoder (List String)
targetSelectedOptions =
    D.at [ "target", "selectedOptions" ] <|
        D.map filteredOptions
            (D.keyValuePairs <|
                D.maybe (D.at [ "value" ] D.string)
            )


filteredOptions : List ( a, Maybe b ) -> List b
filteredOptions list =
    List.filterMap (\( _, mv ) -> mv) list
