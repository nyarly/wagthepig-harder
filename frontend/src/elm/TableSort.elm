module TableSort exposing
    ( SortOrder(..)
    , Sorting
    , builder
    , compareMaybeBools
    , compareMaybes
    , parser
    , sort
    , sortMaybes
    , sortingHeader
    )

import Dict
import Html exposing (Html, text, th)
import Html.Attributes exposing (class)
import Html.Attributes.Extra exposing (empty)
import Html.Events exposing (onClick)
import Url.Builder as B
import Url.Parser.Query as Kewpie exposing (Parser)
import ViewUtil as Eww



{-
   Consumers are expected to implement an enum of things to sort by,
   since they're responsible for sorting by those things
   e.g. consider Date vs Name (& c.f. Events)
-}


type alias Sorting by =
    ( by, SortOrder )


type SortOrder
    = Ascending
    | Descending


parser : Dict.Dict String a -> Parser (Maybe ( a, SortOrder ))
parser sortDict =
    Kewpie.map2 assembleSortOrder
        (Kewpie.enum
            "table_sort"
            sortDict
        )
        (Kewpie.enum
            "table_order"
            (Dict.fromList [ ( "ascd", Ascending ), ( "desc", Descending ) ])
        )


assembleSortOrder : Maybe a -> Maybe SortOrder -> Maybe ( a, SortOrder )
assembleSortOrder maybeBy maybeOrder =
    case ( maybeBy, maybeOrder ) of
        ( Nothing, _ ) ->
            Nothing

        ( Just by, Just Descending ) ->
            Just ( by, Descending )

        ( Just by, _ ) ->
            Just ( by, Ascending )


builder : (a -> String) -> Maybe ( a, SortOrder ) -> List B.QueryParameter
builder byToString maybeSorting =
    case maybeSorting of
        Nothing ->
            []

        Just ( by, order ) ->
            [ B.string "table_sort" (byToString by), B.string "table_order" (orderToString order) ]


orderToString : SortOrder -> String
orderToString order =
    case order of
        Ascending ->
            "ascd"

        Descending ->
            "desc"


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
        class ("sorted_" ++ orderToString order)

    else
        empty


sortIcon : b -> ( b, SortOrder ) -> Html msg
sortIcon by ( s, order ) =
    if s == by then
        Eww.svgIcon ("sort-" ++ orderToString order)

    else
        Eww.svgIcon "sort-none"


sortingHeader : (Sorting d -> msg) -> Sorting d -> String -> d -> Html msg
sortingHeader ev sorting name by =
    th [ onClick (ev (changeSort by sorting)), sortClass by sorting ] [ text name, sortIcon by sorting ]


sortMaybes : (a -> b -> Order) -> Maybe a -> Maybe b -> Order
sortMaybes sortJust ml mr =
    case ( ml, mr ) of
        ( Just l, Just r ) ->
            sortJust l r

        ( Just _, Nothing ) ->
            LT

        ( Nothing, Just _ ) ->
            GT

        ( Nothing, Nothing ) ->
            EQ


compareMaybeBools : Maybe Bool -> Maybe Bool -> Order
compareMaybeBools =
    let
        compareBools l r =
            case ( l, r ) of
                ( True, False ) ->
                    GT

                ( False, True ) ->
                    LT

                ( _, _ ) ->
                    EQ
    in
    sortMaybes compareBools


compareMaybes : Maybe comparable -> Maybe comparable -> Order
compareMaybes =
    sortMaybes compare
