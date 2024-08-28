module Profile exposing (Model, Msg(..), init, view, update)

import Http
import Html exposing (Html, form)
import ViewUtil as Eww

import Json.Decode as D

import Auth
import Hypermedia as HM
import Hypermedia exposing (OperationSelector(..))
import Dict

type Msg
  = Entered Auth.Cred
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

init : Model
init  =
  Model "" "" ""

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
      [ (Eww.inputPair [] "Name" model.name ChangeName)
      , (Eww.inputPair [] "Email" model.email ChangeEmail)
      , (Eww.inputPair [] "BGG Username" model.bgg_username ChangeBGG)
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


fetchProfile : Auth.Cred -> Cmd Msg
fetchProfile creds =
  HM.chain creds [
      HM.browse ["profile"] (ByType "FindAction")|> HM.fillIn (Dict.fromList [("user_id", Auth.accountID creds)])
    ] HM.emptyBody modelRes handleGetResult

modelRes : {a | body: String } -> Result String Model
modelRes res =
  res.body
  |> D.decodeString decoder
  |> Result.mapError D.errorToString

handleGetResult : Result Http.Error Model -> Msg
handleGetResult res =
  case res of
    Ok model -> GotProfile model
    Err err -> ErrProfileGet err
