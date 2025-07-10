module Events exposing (Model, Msg(..), init, updaters, view)

import Auth
import Event
import Html exposing (Html, a, button, h1, table, td, text, th, thead, tr)
import Html.Attributes exposing (class, colspan, href)
import Html.Events exposing (onClick)
import Html.Keyed as Keyed
import Http exposing (Error)
import Hypermedia as HM exposing (Affordance, OperationSelector(..), Uri)
import Iso8601
import Json.Decode as D
import LinkFollowing as HM
import Router exposing (EventSortBy(..))
import TableSort exposing (SortOrder(..))
import Time
import Updaters exposing (Updater)


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


type alias Interface base model msg =
    { base
        | localUpdate : Updater Model Msg -> Updater model msg
        , requestCreateEvent : Affordance -> Updater model msg
        , requestUpdatePath : Router.Target -> Updater model msg
        , handleError : Error -> Updater model msg
    }



-- updaters : Interface base model msg -> Msg -> UpdateList model msg


updaters :
    Interface iface model msg
    -> Msg
    -> Updater model msg
updaters { localUpdate, requestCreateEvent, requestUpdatePath, handleError } msg =
    case msg of
        Entered creds _ ->
            localUpdate (\model -> ( { model | creds = creds }, fetch creds ))

        GotEvents new ->
            localUpdate (\m -> ( { m | resource = new }, Cmd.none ))

        ChangeSort newsort ->
            requestUpdatePath (Router.Events (Just newsort))

        ErrGetEvents err ->
            handleError err

        CreateNewEvent aff ->
            requestCreateEvent aff


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
            sortDefault maybeSort

        sortingHeader =
            TableSort.sortingHeader ChangeSort sorting

        sortEvents events =
            TableSort.sort sortWith sorting events
    in
    [ h1 [] [ text "Events" ]
    , createEventButton model.resource
    , table []
        [ thead []
            [ sortingHeader "Name" [ class "name" ] EventName
            , sortingHeader "Date" [ class "date" ] Date
            , sortingHeader "Where" [ class "location" ] Location
            , th [ colspan 3 ] []
            ]
        , Keyed.node "tbody" [] (List.map makeRow (sortEvents model.resource.events))
        ]
    ]


makeRow : Event -> ( String, Html Msg )
makeRow event =
    ( event.id
    , tr []
        [ td [ class "name" ] [ text event.name ]
        , td [ class "date" ] [ text (Event.formatTime event) ]
        , td [ class "location" ] [ text event.location ]
        , td [ class "show" ] [ eventShowButton event ]
        , td [ class "edit" ] [ eventEditButton event ]
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
    HM.chain
        [ HM.browse [ "events" ] (HM.ByType "ViewAction")
        ]
        (Auth.credHeader creds)
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
