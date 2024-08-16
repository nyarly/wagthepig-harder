module Events exposing (Model, Msg(..), init, view, update)

import Time
import Json.Decode as D

import Api
import Http
import Html exposing (Html, h1, text, table, thead, th, tbody, tr, td)
import Html.Attributes exposing (colspan)

type Msg
  = Entered Api.Cred
  | GotEvents Model
  | ErrGetEvents Http.Error

type alias IRI = String

type alias Model =
  { id: Maybe IRI
  , events: List(Event)
  , operation: List(Operation)
  }

type alias Operation =
  { method: String
  }

type alias Event =
  { id: IRI
  , name: String
  , time: Time.Posix
  , location: String
  }

init : Model
init =
  Model Nothing [] []

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
  case msg of
    Entered creds -> (model, fetch creds)
    GotEvents new -> (new, Cmd.none)
    ErrGetEvents _ -> (model, Cmd.none) -- XXX


view : Model -> List (Html Msg)
view model =
  [ h1 [] [ text "Events" ]
  , table []
    [ thead []
        [ th [] [ text "Name" ]
        , th [] [ text "Date" ]
        , th [] [ text "Where" ]
        , th [ colspan 3 ] []
        ]
    , tbody [] (List.foldr addRow [] model.events)
    ]
  ]

addRow : Event -> List (Html Msg) -> List (Html Msg)
addRow event list =
  (tr []
    [ td [] [ text event.name ]
    , td [] [ text (String.fromInt (Time.posixToMillis event.time)) ]
    , td [] [ text event.location ]
    , td [] [ text "Show" ]
    , td [] [ text "Edit" ]
  ]) :: list


fetch: Api.Cred -> Cmd Msg
fetch creds =
  Api.chain creds [(Api.linkByName "events")] "GET" Http.emptyBody modelRes handleGetResult

handleGetResult : Result Http.Error Model -> Msg
handleGetResult res =
  case res of
    Ok model -> GotEvents model
    Err err -> ErrGetEvents err

-- type alias HeadersAndBodyToRes a = (Headers -> Body -> Result String a)

modelRes : a -> String -> Result String Model
modelRes _ body =
  body
  |> D.decodeString decoder
  |> Result.mapError D.errorToString


decoder : D.Decoder Model
decoder =
  D.map3 Model
    (D.map Just (D.field "@id" D.string))
    (D.field "events" (D.list itemDecoder))
    (D.field "operation" (D.list opDecoder))

itemDecoder : D.Decoder Event
itemDecoder =
  D.map4 Event
    (D.field "@id" D.string)
    (D.field "name" D.string)
    (D.field "time" (D.map Time.millisToPosix D.int))
    (D.field "location" D.string)

opDecoder : D.Decoder Operation
opDecoder =
  D.map Operation
    (D.field "method" D.string)
