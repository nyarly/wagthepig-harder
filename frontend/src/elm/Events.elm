module Events exposing (Model, Msg(..), bidiupdate, init, view)

import Auth
import Html exposing (Html, a, button, h1, table, td, text, th, thead, tr)
import Html.Attributes exposing (colspan)
import Html.Events exposing (onClick)
import Html.Keyed as Keyed
import Http
import Hypermedia as HM exposing (Affordance, OperationSelector(..), Uri)
import Iso8601
import Json.Decode as D
import OutMsg
import TableSort
import Time


type alias Model =
    { creds : Auth.Cred
    , sorting : TableSort.Sorting SortBy
    , resource : Resource
    }


type alias Resource =
    { id : Maybe Uri
    , events : List Event
    , affordances : List Affordance
    }


type alias Event =
    { id : Uri
    , name : String
    , time : Time.Posix
    , location : String
    , affordances : List Affordance
    }


type SortBy
    = Name
    | Date
    | Location


decoder : D.Decoder Resource
decoder =
    D.map3 Resource
        (D.map Just (D.field "id" D.string))
        (D.field "events" (D.list itemDecoder))
        HM.affordanceListDecoder


itemDecoder : D.Decoder Event
itemDecoder =
    D.map5 Event
        (D.field "id" D.string)
        (D.field "name" D.string)
        (D.field "time" Iso8601.decoder)
        (D.field "location" D.string)
        HM.affordanceListDecoder


type Msg
    = Entered Auth.Cred
    | GotEvents Resource
    | ErrGetEvents Http.Error
    | CreateNewEvent Affordance
    | EditEvent Affordance
    | ChangeSort SortBy


init : Model
init =
    Model
        Auth.unauthenticated
        ( Date, TableSort.Descending )
        (Resource Nothing [] [])


bidiupdate : Msg -> Model -> ( Model, Cmd Msg, OutMsg.Msg )
bidiupdate msg model =
    case msg of
        Entered creds ->
            ( model, fetch creds, OutMsg.None )

        GotEvents new ->
            ( { model | resource = new }, Cmd.none, OutMsg.None )

        ErrGetEvents _ ->
            ( model, Cmd.none, OutMsg.None )

        -- XXX
        CreateNewEvent aff ->
            ( model, Cmd.none, OutMsg.Page << OutMsg.CreateEvent <| aff )

        EditEvent aff ->
            ( model, Cmd.none, OutMsg.Page (OutMsg.EditEvent model.creds aff) )

        ChangeSort by ->
            ( { model | sorting = TableSort.changeSort by model.sorting }, Cmd.none, OutMsg.None )


sortWith : SortBy -> Event -> Event -> Order
sortWith by l r =
    case by of
        Name ->
            compare l.name r.name

        Location ->
            compare l.location r.location

        Date ->
            let
                millis =
                    \e -> e.time |> Time.posixToMillis
            in
            compare (millis l) (millis r)


sortEvents : TableSort.Sorting SortBy -> List Event -> List Event
sortEvents sorting events =
    TableSort.sort sortWith sorting events


view : Model -> List (Html Msg)
view model =
    let
        sortingHeader =
            TableSort.sortingHeader ChangeSort model
    in
    [ h1 [] [ text "Events" ]
    , createEventButton model.resource
    , table []
        [ thead []
            [ sortingHeader "Name" Name
            , sortingHeader "Date" Date
            , sortingHeader "Where" Location
            , th [ colspan 3 ] []
            ]
        , Keyed.node "tbody" [] (List.foldr addRow [] (sortEvents model.sorting model.resource.events))
        ]
    ]


addRow : Event -> List ( String, Html Msg ) -> List ( String, Html Msg )
addRow event list =
    ( event.id
    , tr []
        [ td [] [ text event.name ]
        , td [] [ text (formatEventTime event) ]
        , td [] [ text event.location ]
        , td [] [ text "Show" ]
        , td [] [ eventEditButton event ]
        ]
    )
        :: list


formatEventTime : { a | time : Time.Posix } -> String
formatEventTime event =
    -- Thu Mar 31, 2024
    formatWeekday event.time
        ++ " "
        ++ formatMonth event.time
        ++ " "
        ++ String.fromInt
            (Time.toDay Time.utc event.time)
        ++ ", "
        ++ String.fromInt (Time.toYear Time.utc event.time)


createEventButton : Resource -> Html Msg
createEventButton eventlist =
    case HM.selectAffordance (HM.ByType "AddAction") eventlist.affordances of
        Just aff ->
            button [ onClick (CreateNewEvent aff) ] [ text "Create Event" ]

        Nothing ->
            button [] [ text "event creation not available" ]


eventEditButton : Event -> Html Msg
eventEditButton event =
    case HM.selectAffordance (HM.ByType "UpdateAction") event.affordances of
        Just aff ->
            a [ onClick (EditEvent aff) ] [ text "Edit" ]

        Nothing ->
            text "Edit"


fetch : Auth.Cred -> Cmd Msg
fetch creds =
    HM.chain creds
        [ HM.browse [ "events" ] (HM.ByType "ViewAction")
        ]
        Http.emptyBody
        modelRes
        handleGetResult


handleGetResult : Result Http.Error Resource -> Msg
handleGetResult res =
    case res of
        Ok model ->
            GotEvents model

        Err err ->
            ErrGetEvents err



-- type alias ResponseToResult a = (Response -> Result String a)


modelRes : { a | body : String } -> Result String Resource
modelRes res =
    res.body
        |> D.decodeString decoder
        |> Result.mapError D.errorToString


formatWeekday : Time.Posix -> String
formatWeekday posix =
    case Time.toWeekday Time.utc posix of
        Time.Mon ->
            "Mon"

        Time.Tue ->
            "Tue"

        Time.Wed ->
            "Wed"

        Time.Thu ->
            "Thu"

        Time.Fri ->
            "Fri"

        Time.Sat ->
            "Sat"

        Time.Sun ->
            "Sun"


formatMonth : Time.Posix -> String
formatMonth posix =
    case Time.toMonth Time.utc posix of
        Time.Jan ->
            "Jan"

        Time.Feb ->
            "Feb"

        Time.Mar ->
            "Mar"

        Time.Apr ->
            "Apr"

        Time.May ->
            "May"

        Time.Jun ->
            "Jun"

        Time.Jul ->
            "Jul"

        Time.Aug ->
            "Aug"

        Time.Sep ->
            "Sep"

        Time.Oct ->
            "Oct"

        Time.Nov ->
            "Nov"

        Time.Dec ->
            "Dec"
