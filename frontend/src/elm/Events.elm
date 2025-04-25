module Events exposing (Model, Msg(..), bidiupdate, init, view)

import Auth
import Event
import Html exposing (Html, a, button, h1, table, td, text, th, thead, tr)
import Html.Attributes exposing (colspan, href)
import Html.Events exposing (onClick)
import Html.Keyed as Keyed
import Http
import Hypermedia as HM exposing (Affordance, OperationSelector(..), Uri)
import Iso8601
import Json.Decode as D
import OutMsg
import Router exposing (EventSortBy(..))
import TableSort exposing (SortOrder(..))
import Time


type alias TableSorting =
    TableSort.Sorting EventSortBy


type alias Model =
    { creds : Auth.Cred
    , resource : Resource
    }


type alias Resource =
    { id : Maybe Uri
    , events : List Event
    , affordances : List Affordance
    }


type alias Event =
    { id : Uri
    , nick : EventNick
    , name : String
    , time : Time.Posix
    , location : String
    , affordances : List Affordance
    }


type alias EventNick =
    { event_id : EventId }


type alias EventId =
    Int


sortDefault : Maybe ( EventSortBy, SortOrder ) -> ( EventSortBy, SortOrder )
sortDefault =
    Maybe.withDefault ( Date, Descending )


decoder : D.Decoder Resource
decoder =
    D.map3 Resource
        (D.map Just (D.field "id" D.string))
        (D.field "events" (D.list itemDecoder))
        HM.affordanceListDecoder


itemDecoder : D.Decoder Event
itemDecoder =
    D.map6 Event
        (D.field "id" D.string)
        (D.field "nick" nickDecoder)
        (D.field "name" D.string)
        (D.field "time" Iso8601.decoder)
        (D.field "location" D.string)
        HM.affordanceListDecoder


nickDecoder : D.Decoder EventNick
nickDecoder =
    D.map EventNick (D.field "event_id" D.int)


type Msg
    = Entered Auth.Cred (Maybe TableSorting)
    | GotEvents Resource
    | ErrGetEvents Http.Error
    | CreateNewEvent Affordance
    | ChangeSort TableSorting


init : Model
init =
    Model
        Auth.unauthenticated
        (Resource Nothing [] [])


bidiupdate : Msg -> Model -> ( Model, Cmd Msg, OutMsg.Msg )
bidiupdate msg model =
    case msg of
        Entered creds _ ->
            ( { model | creds = creds }, fetch creds, OutMsg.None )

        GotEvents new ->
            ( { model | resource = new }, Cmd.none, OutMsg.None )

        ChangeSort newsort ->
            ( model, Cmd.none, OutMsg.Main << OutMsg.UpdatePage << Router.Events << Just <| newsort )

        ErrGetEvents _ ->
            ( model, Cmd.none, OutMsg.None )

        -- XXX
        CreateNewEvent aff ->
            ( model, Cmd.none, OutMsg.Page << OutMsg.CreateEvent <| aff )


sortWith : EventSortBy -> Event -> Event -> Order
sortWith by l r =
    case by of
        EventName ->
            compare l.name r.name

        Location ->
            compare l.location r.location

        Date ->
            let
                millis =
                    \e -> e.time |> Time.posixToMillis
            in
            compare (millis l) (millis r)


view : Model -> Maybe TableSorting -> List (Html Msg)
view model maybeSort =
    let
        sorting =
            sortDefault (Debug.log "event-sort" maybeSort)

        sortingHeader =
            TableSort.sortingHeader ChangeSort sorting

        sortEvents events =
            TableSort.sort sortWith sorting events
    in
    [ h1 [] [ text "Events" ]
    , createEventButton model.resource
    , table []
        [ thead []
            [ sortingHeader "Name" EventName
            , sortingHeader "Date" Date
            , sortingHeader "Where" Location
            , th [ colspan 3 ] []
            ]
        , Keyed.node "tbody" [] (List.map makeRow (sortEvents model.resource.events))
        ]
    ]


makeRow : Event -> ( String, Html Msg )
makeRow event =
    ( event.id
    , tr []
        [ td [] [ text event.name ]
        , td [] [ text (Event.formatTime event) ]
        , td [] [ text event.location ]
        , td [] [ eventShowButton event ]
        , td [] [ eventEditButton event ]
        ]
    )


createEventButton : Resource -> Html Msg
createEventButton eventlist =
    case HM.selectAffordance (HM.ByType "AddAction") eventlist.affordances of
        Just aff ->
            button [ onClick (CreateNewEvent aff) ] [ text "Create Event" ]

        Nothing ->
            button [] [ text "event creation not available" ]


eventEditButton : Event -> Html Msg
eventEditButton event =
    a [ href (Router.buildFromTarget (Router.EventEdit event.nick.event_id)) ] [ text "Edit" ]


eventShowButton : Event -> Html Msg
eventShowButton event =
    a [ href (Router.buildFromTarget (Router.EventShow event.nick.event_id Nothing)) ] [ text "Show" ]


fetch : Auth.Cred -> Cmd Msg
fetch creds =
    HM.chain creds
        [ HM.browse [ "events" ] (HM.ByType "ViewAction")
        ]
        []
        Http.emptyBody
        (HM.decodeBody decoder)
        handleGetResult


handleGetResult : Result Http.Error Resource -> Msg
handleGetResult res =
    case res of
        Ok model ->
            GotEvents model

        Err err ->
            ErrGetEvents err
