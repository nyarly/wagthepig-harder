module EventEdit exposing
    ( Bookmark(..)
    , Model
    , Msg(..)
    , Toast
    , forCreate
    , init
    , updaters
    , view
    , viewToast
    )

import Auth
import Event exposing (browseToEvent, nickToVars)
import Html exposing (Html, button, div, form, p, text)
import Html.Attributes exposing (class, disabled, id, step, type_, value)
import Html.Attributes.Extra as Attr
import Html.Events exposing (onClick, onSubmit)
import Http exposing (Error(..))
import Hypermedia as HM exposing (Affordance, Method(..), OperationSelector(..))
import Iso8601
import Json.Decode as D
import Json.Encode as E
import ResourceUpdate as Up exposing (apiRoot, resultDispatch)
import Task
import Time
import Toast
import Updaters exposing (Tried, Updater, entryUpdater, noChange)
import ViewUtil as Eww


type alias Model =
    { creds : Auth.Cred
    , etag : Up.Etag
    , resource : Resource
    , retry : Maybe (Tried Msg Int)
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


type Toast
    = Retryable (Tried Msg Int)
    | Unknown


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
        Nothing



-- XXX baby jesus cries


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
        Nothing


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
    | GotEvent Up.Etag Resource
    | ErrGetEvent HM.Error
    | Retry Msg


view : Model -> List (Html Msg)
view model =
    let
        ev =
            model.resource
    in
    [ form [ onSubmit Submit ]
        [ Eww.inputPair [] "Name" ev.name ChangeName
        , Eww.inputPair [ type_ "datetime-local", step "60", value (timeWithMinutes ev.time) ] "Time" (Iso8601.fromTime ev.time |> String.dropRight 1) ChangeTime
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


timeWithMinutes : Time.Posix -> String
timeWithMinutes time =
    Iso8601.fromTime time
        |> String.dropRight 8


viewToast : Toast.Info Toast -> List (Html Msg)
viewToast toastInfo =
    case toastInfo.content of
        Retryable r ->
            [ p []
                [ text "There was a hiccup editing an event" ]
            , button [ onClick (Retry r.msg) ] [ text "Retry" ]
            ]

        Unknown ->
            [ text "something went wrong editing an event" ]


type alias Interface base model msg =
    { base
        | localUpdate : Updater Model Msg -> Updater model msg
        , sendToast : Toast -> Updater model msg
        , lowerModel : model -> Model
        , relogin : Updater model msg
        , handleErrorWithRetry : Updater model msg -> Error -> Updater model msg
    }


updaters : Interface base model msg -> Msg -> Updater model msg
updaters ({ localUpdate, handleErrorWithRetry, sendToast } as iface) msg =
    let
        updateRes f =
            localUpdate (\m -> ( { m | resource = f m.resource }, Cmd.none ))

        justTried model =
            Just (Tried msg model.resource.nick)
    in
    case msg of
        Entered creds loc ->
            case loc of
                -- creating a new Event
                None ->
                    localUpdate (\m -> ( { m | creds = creds }, getCurrentTime ))

                Nickname id ->
                    let
                        fetchUpdater m =
                            ( { m | creds = creds, retry = justTried m }
                            , fetchByNick creds id
                            )

                        retryUpdater m =
                            ( { m | creds = creds }, Cmd.none )
                    in
                    entryUpdater iface fetchUpdater retryUpdater updaters id

        TimeNow t ->
            updateRes (\r -> { r | time = t })

        ChangeName n ->
            updateRes (\r -> { r | name = n })

        ChangeTime t ->
            case Iso8601.toTime t of
                Ok nt ->
                    updateRes (\r -> { r | time = nt })

                Err _ ->
                    sendToast Unknown

        ChangeLocation l ->
            updateRes (\r -> { r | location = l })

        -- XXX
        Submit ->
            localUpdate (\m -> ( { m | retry = justTried m }, putEvent m.creds m ))

        GotEvent etag ev ->
            localUpdate (\m -> ( { m | etag = etag, resource = ev, retry = Nothing }, Cmd.none ))

        ErrGetEvent err ->
            handleErrorWithRetry (maybeRetry iface) err

        Retry m ->
            case m of
                Retry _ ->
                    noChange

                _ ->
                    updaters iface m


maybeRetry :
    { iface
        | sendToast : Toast -> Updater model msg
        , lowerModel : model -> Model
    }
    -> Updater model msg
maybeRetry { sendToast, lowerModel } model =
    let
        toast =
            case (lowerModel model).retry of
                Just r ->
                    Retryable r

                Nothing ->
                    Unknown
    in
    sendToast toast model


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
                , resMsg = resultDispatch ErrGetEvent (\( etag, ps ) -> GotEvent etag ps)
                , startAt = aff
                , browsePlan = [] -- List AffordanceExtractor
                , headers = Auth.credHeader creds -- Auth.Cred
                }

        Nothing ->
            Cmd.none


fetchByNick : Auth.Cred -> Int -> Cmd Msg
fetchByNick creds id =
    Up.retrieve
        { headers = Auth.credHeader creds
        , decoder = decoder
        , resMsg = resultDispatch ErrGetEvent (\( etag, ps ) -> GotEvent etag ps)
        , startAt = apiRoot
        , browsePlan = browseToEvent (nickToVars id)
        }
