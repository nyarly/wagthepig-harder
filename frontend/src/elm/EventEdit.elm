module EventEdit exposing (Bookmark(..), Model, Msg(..), bidiupdate, forCreate, init, view)

import Auth
import Event exposing (browseToEvent, nickToVars)
import Html exposing (Html, button, div, form, text)
import Html.Attributes exposing (class, disabled, id, type_)
import Html.Attributes.Extra as Attr
import Html.Events exposing (onSubmit)
import Hypermedia as HM exposing (Affordance, Method(..), OperationSelector(..))
import Iso8601
import Json.Decode as D
import Json.Encode as E
import OutMsg
import ResourceUpdate as Up exposing (apiRoot, resultDispatch)
import Task
import Time
import ViewUtil as Eww


type alias Model =
    { creds : Auth.Cred
    , etag : Up.Etag
    , resource : Resource
    }


type alias Resource =
    { id : Maybe Affordance
    , nick : Int
    , template : Maybe Affordance
    , update : Maybe Affordance
    , name : String
    , time : Time.Posix
    , location : String
    }


type Bookmark
    = None
    | Nickname Int
    | Url HM.Uri


init : Model
init =
    Model
        Auth.unauthenticated
        Nothing
        (Resource
            Nothing
            0
            Nothing
            Nothing
            ""
            (Time.millisToPosix 0)
            ""
        )


forCreate : Affordance -> Model
forCreate aff =
    Model
        Auth.unauthenticated
        Nothing
        (Resource
            Nothing
            0
            Nothing
            (Just aff)
            ""
            (Time.millisToPosix 0)
            ""
        )


encodeEvent : Resource -> E.Value
encodeEvent ev =
    E.object
        [ ( "name", E.string ev.name )
        , ( "time", Iso8601.encode ev.time )
        , ( "location", E.string ev.location )
        ]


decoder : D.Decoder Resource
decoder =
    D.map7 Resource
        (D.map (\u -> Just (HM.link GET u)) (D.field "id" D.string))
        (D.at [ "nick", "event_id" ] D.int)
        (D.map (HM.selectAffordance (ByType "FindAction")) HM.affordanceListDecoder)
        (D.map (HM.selectAffordance (ByType "UpdateAction")) HM.affordanceListDecoder)
        (D.field "name" D.string)
        (D.field "time" Iso8601.decoder)
        (D.field "location" D.string)


type Msg
    = Entered Auth.Cred Bookmark
    | TimeNow Time.Posix
    | ChangeName String
    | ChangeTime String
    | ChangeLocation String
    | Submit
    | GotEvent Up.Etag Resource OutMsg.Msg
    | ErrGetEvent HM.Error


view : Model -> List (Html Msg)
view model =
    let
        ev =
            model.resource
    in
    [ form [ onSubmit Submit ]
        [ Eww.inputPair [] "Name" ev.name ChangeName
        , Eww.inputPair [ type_ "datetime-local" ] "Time" (Iso8601.fromTime ev.time |> String.dropRight 1) ChangeTime
        , Eww.inputPair [] "Location" ev.location ChangeLocation
        , div [ class "actions" ]
            [ button
                [ case model.resource.update of
                    Just _ ->
                        Attr.empty

                    Nothing ->
                        disabled True
                ]
                [ text "Submit" ]
            ]
        ]
    ]


bidiupdate : Msg -> Model -> ( Model, Cmd Msg, OutMsg.Msg )
bidiupdate msg model =
    let
        updateRes f m =
            { m | resource = f m.resource }
    in
    case msg of
        Entered creds loc ->
            case loc of
                None ->
                    ( { model | creds = creds }, getCurrentTime, OutMsg.None )

                -- creating a new Event
                Nickname id ->
                    ( { model | creds = creds }, fetchByNick creds id, OutMsg.None )

                Url url ->
                    ( { model | creds = creds }, fetchFromUrl creds url, OutMsg.None )

        TimeNow t ->
            ( updateRes (\r -> { r | time = t }) model, Cmd.none, OutMsg.None )

        ChangeName n ->
            ( updateRes (\r -> { r | name = n }) model, Cmd.none, OutMsg.None )

        ChangeTime t ->
            case Iso8601.toTime t of
                Ok nt ->
                    ( updateRes (\r -> { r | time = nt }) model, Cmd.none, OutMsg.None )

                Err _ ->
                    ( model, Cmd.none, OutMsg.None )

        -- XXX silent rejection of errors :(
        ChangeLocation l ->
            ( updateRes (\r -> { r | location = l }) model, Cmd.none, OutMsg.None )

        GotEvent etag ev outmsg ->
            ( { model | etag = etag, resource = ev }, Cmd.none, outmsg )

        ErrGetEvent _ ->
            ( model, Cmd.none, OutMsg.None )

        -- XXX
        Submit ->
            ( model, putEvent model.creds model, OutMsg.None )


getCurrentTime : Cmd Msg
getCurrentTime =
    Task.perform TimeNow Time.now


putEvent : Auth.Cred -> Model -> Cmd Msg
putEvent creds model =
    -- Up.put encodeEvent decoder (makeMsg creds) creds model.etag model.resource
    case model.resource.update of
        Just aff ->
            Up.update
                { resource = model.resource -- s
                , etag = Just model.etag -- Maybe Etag
                , encode = encodeEvent -- s -> E.Value
                , decoder = decoder -- D.Decoder r
                , resMsg = resultDispatch ErrGetEvent (\( etag, ps ) -> GotEvent etag ps OutMsg.None)
                , startAt = aff
                , browsePlan = [] -- List AffordanceExtractor
                , creds = creds -- Auth.Cred
                }

        Nothing ->
            Cmd.none


fetchByNick : Auth.Cred -> Int -> Cmd Msg
fetchByNick creds id =
    Up.retrieve
        { creds = creds
        , decoder = decoder
        , resMsg = resultDispatch ErrGetEvent (\( etag, ps ) -> GotEvent etag ps OutMsg.None)
        , startAt = apiRoot
        , browsePlan = browseToEvent (nickToVars id)
        }


fetchFromUrl : Auth.Cred -> HM.Uri -> Cmd Msg
fetchFromUrl creds url =
    Up.retrieve
        { creds = creds
        , decoder = decoder

        -- XXX used to update path with stuff
        , resMsg = resultDispatch ErrGetEvent (\( etag, ps ) -> GotEvent etag ps OutMsg.None)
        , startAt = HM.link HM.GET url
        , browsePlan = []
        }
