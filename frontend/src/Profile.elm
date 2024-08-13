module Profile exposing (Model, Msg(..), init, view, update)

import Http
import Html exposing (Html, Attribute, div, form, input, label, text)
import Html.Attributes exposing (for, id, value)
import Html.Events exposing (onInput)

import Json.Decode as D

import Api
import Html.Attributes exposing (class)

type Msg
  = Entered Api.Cred
  | ChangeEmail String
  | ChangeName String
  | ChangeBGG String
  | GotProfile Model
  | ErrProfileGet Http.Error

type alias Model =
  { name : String
  , email : String
  , bgg_username: String
  }

init : Api.Cred -> ( Model, Cmd Msg )
init cred =
    (
        Model "" "" "",
        fetchProfile cred
    )

decoder : D.Decoder Model
decoder =
  D.map3 Model
    (D.field "name" D.string)
    (D.field "email" D.string)
    (D.field "bgg_username" D.string)

view : Model -> List (Html Msg)
view model =
  [
    form []
      [ (inputPair [] "Name" model.name ChangeName)
      , (inputPair [] "Email" model.email ChangeEmail)
      , (inputPair [] "BGG Username" model.bgg_username ChangeBGG)
      ]
  ]

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
  case msg of
    Entered creds -> (model, fetchProfile creds)
    ChangeName n -> ({ model | name = n}, Cmd.none)
    ChangeEmail e -> ({ model | email = e}, Cmd.none)
    ChangeBGG b -> ({ model | bgg_username = b}, Cmd.none)
    GotProfile m -> (m, Cmd.none)
    ErrProfileGet _ -> (model, Cmd.none) -- XXX


fetchProfile : Api.Cred -> Cmd Msg
fetchProfile creds =
-- get : Maybe Cred -> String -> Decoder a -> ResToMsg Http.Error a msg -> Cmd msg
  Api.get creds ("/api/profile/" ++ Api.accountID creds) decoder handleGetResult -- XXX h/c URL

handleGetResult : Result Http.Error Model -> Msg
handleGetResult res =
  case res of
    Ok model -> GotProfile model
    Err err -> ErrProfileGet err


inputPair : List (Attribute msg) -> String -> String -> (String -> msg) -> Html msg
inputPair attrs name v event =
  let
      pid = String.toLower name
  in
    div [ class "field" ]
    [ label [ for pid ] [ text name ]
    , input ([ id pid, onInput event, value v ] ++ attrs) []
    ]
