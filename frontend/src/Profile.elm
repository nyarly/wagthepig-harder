module Profile exposing (Model, Bookmark(..), Msg(..), init, view, bidiupdate)

import Http
import Html exposing (Html, form, button, text)
import Html.Events exposing (onSubmit)
import Html.Attributes exposing (disabled)
import Html.Attributes.Extra exposing (attributeMaybe)

import Json.Decode as D
import Json.Encode as E
import Dict

import Auth
import Hypermedia as HM exposing (OperationSelector(..), Affordance)
import ViewUtil as Eww
import OutMsg
import Router
import ResourceUpdate as Up

type Bookmark
  = None
  | Nickname
  | Url Affordance

type Msg
  = Entered Auth.Cred Bookmark
  | ChangeEmail String
  | ChangeName String
  | ChangeBGG String
  | GotProfile Profile OutMsg.Msg
  | ErrProfileGet Http.Error
  | Submit

type alias Model =
  { creds: Auth.Cred
  , profile: Profile
  }

type alias Profile =
  { name : String
  , email : String
  , bgg_username: String
  , update: Maybe Affordance
  , template: Maybe Affordance
  }

init : Model
init  =
  Model
    Auth.unauthenticated
    (Profile "" "" "" Nothing Nothing)

encode : Profile -> E.Value
encode profile =
  E.object
    [ ("name", E.string profile.name)
    , ("email", E.string profile.email)
    , ("bgg_username", E.string profile.bgg_username)
    ]

decoder : D.Decoder Profile
decoder =
  D.map5 Profile
    (D.field "name" D.string)
    (D.field "email" D.string)
    (D.field "bgg_username" D.string)
    (D.map (\laff -> HM.selectAffordance (ByType "UpdateAction") laff) HM.affordanceListDecoder)
    (D.map (\laff -> HM.selectAffordance (ByType "ViewAction") laff) HM.affordanceListDecoder)

view : Model -> List (Html Msg)
view model =
  [
    form [ onSubmit Submit ]
      [ (Eww.inputPair [] "Name" model.profile.name ChangeName)
      , (Eww.inputPair [] "Email" model.profile.email ChangeEmail)
      , (Eww.inputPair [] "BGG Username" model.profile.bgg_username ChangeBGG)
      , button [ attributeMaybe (\_ -> disabled True) model.profile.update ] [ text "Update Profile" ]
      ]
  ]

bidiupdate : Msg -> Model -> ( Model, Cmd Msg, OutMsg.Msg )
bidiupdate msg model =
  case msg of
    Entered creds loc ->
      case loc of
        None -> ({init | creds = creds}, Cmd.none, OutMsg.None) -- creating a new Event
        Nickname -> ({model | creds = creds}, fetchByCreds creds model, OutMsg.None)
        Url url -> ({model | creds = creds}, fetchFromUrl creds url, OutMsg.None )

    ChangeName n ->
      let
        profile = model.profile
        res = {profile | name = n}
      in
        ({ model | profile = res}, Cmd.none, OutMsg.None)
    ChangeEmail e ->
      let
        profile = model.profile
        res = {profile | email = e}
      in
        ({ model | profile = res}, Cmd.none, OutMsg.None)
    ChangeBGG b ->
      let
        profile = model.profile
        res = {profile | bgg_username = b}
      in
        ({ model | profile = res}, Cmd.none, OutMsg.None)
    GotProfile m out -> ({ model | profile = m}, Cmd.none, out)
    ErrProfileGet _ -> (model, Cmd.none, OutMsg.None) -- XXX
    Submit -> (model, putProfile model.creds model, OutMsg.None)

makeMsg : Auth.Cred -> Up.Representation Profile -> Msg
makeMsg cred rep =
  case rep of
    Up.None -> Entered cred None
    Up.Loc aff -> Entered cred (Url aff)
    Up.Res res out -> GotProfile res out
    Up.Error err -> ErrProfileGet err

nickToVars : String -> Dict.Dict String String
nickToVars nick =
  (Dict.fromList [("user_id", nick)])

browseToProfile : HM.TemplateVars -> List (HM.Response -> Result String Affordance)
browseToProfile vars =
  [ HM.browse ["profile"] (ByType "FindAction")|> HM.fillIn vars ]

putProfile : Auth.Cred -> Model -> Cmd Msg
putProfile creds model =
  Up.put encode decoder (makeMsg creds) creds model.profile

fetchByCreds : Auth.Cred -> Model -> Cmd Msg
fetchByCreds creds model =
  Up.fetchByNick decoder (makeMsg creds) nickToVars browseToProfile model.profile.template creds (Auth.accountID creds)

fetchFromUrl : Auth.Cred -> Affordance -> Cmd Msg
fetchFromUrl creds url =
  Up.fetchFromUrl decoder (makeMsg creds) (\_ -> Router.Profile) creds url
