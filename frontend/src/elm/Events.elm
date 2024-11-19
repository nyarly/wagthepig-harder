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
import Time


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
    , name : String
    , time : Time.Posix
    , location : String
    , affordances : List Affordance
    }


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


init : Model
init =
    Model
        Auth.unauthenticated
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


view : Model -> List (Html Msg)
view model =
    [ h1 [] [ text "Events" ]
    , createEventButton model.resource
    , table []
        [ thead []
            [ th [] [ text "Name" ]
            , th [] [ text "Date" ]
            , th [] [ text "Where" ]
            , th [ colspan 3 ] []
            ]
        , Keyed.node "tbody" [] (List.foldr addRow [] model.resource.events)
        ]
    ]


createEventButton : Resource -> Html Msg
createEventButton eventlist =
    case HM.selectAffordance (HM.ByType "AddAction") eventlist.affordances of
        Just aff ->
            button [ onClick (CreateNewEvent aff) ] [ text "Create Event" ]

        Nothing ->
            button [] [ text "event creation not available" ]


addRow : Event -> List ( String, Html Msg ) -> List ( String, Html Msg )
addRow event list =
    ( event.id
    , tr []
        [ td [] [ text event.name ]
        , td [] [ text (String.fromInt (Time.posixToMillis event.time)) ]
        , td [] [ text event.location ]
        , td [] [ text "Show" ]
        , td [] [ eventEditButton event ]
        ]
    )
        :: list


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
