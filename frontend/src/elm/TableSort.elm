module TableSort exposing (..)

import Html exposing (Html, a, button, h1, table, td, text, th, thead, tr)
import Html.Attributes exposing (class, colspan)
import Html.Attributes.Extra exposing (empty)
import Html.Events exposing (onClick)
import ViewUtil as Eww


type alias Sorting by =
    ( by, SortOrder )


type SortOrder
    = Ascending
    | Descending


changeSort : b -> ( b, SortOrder ) -> ( b, SortOrder )
changeSort by ( s, order ) =
    if s == by && order == Ascending then
        ( s, Descending )

    else
        ( by, Ascending )


sort : (b -> item -> item -> Order) -> ( b, SortOrder ) -> List item -> List item
sort sorter ( by, order ) list =
    let
        sortf =
            sorter by

        base =
            List.sortWith sortf list
    in
    case order of
        Ascending ->
            base

        Descending ->
            List.reverse base


sortClass : b -> ( b, SortOrder ) -> Html.Attribute msg
sortClass by ( s, order ) =
    if s == by then
        case order of
            Ascending ->
                class "sorted_asc"

            Descending ->
                class "sorted_desc"

    else
        empty


sortIcon : b -> ( b, SortOrder ) -> Html msg
sortIcon by ( s, order ) =
    if s == by then
        case order of
            Ascending ->
                Eww.svgIcon "sort-ascd"

            Descending ->
                Eww.svgIcon "sort-desc"

    else
        Eww.svgIcon "sort-none"


sortingHeader ev model name by =
    th [ onClick (ev by), sortClass by model.sorting ] [ text name, sortIcon by model.sorting ]
