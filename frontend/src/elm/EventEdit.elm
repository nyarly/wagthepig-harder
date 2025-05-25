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
import Html exposing (Html, a, button, div, form, p, text)
import Html.Attributes exposing (class, disabled, href, id, type_)
import Html.Attributes.Extra as Attr
import Html.Events exposing (onClick, onSubmit)
import Http exposing (Error(..))
import Hypermedia as HM exposing (Affordance, Method(..), OperationSelector(..))
import Iso8601
import Json.Decode as D
import Json.Encode as E
import ResourceUpdate as Up exposing (apiRoot, resultDispatch)
import Router
import Task
import Time
import Toast
import Updaters exposing (UpdateList, Updater)
import ViewUtil as Eww


type alias Model =
    { creds : Auth.Cred
    , etag : Up.Etag
    , resource : Resource
    , retry : Maybe (Cmd Msg)
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


type Toast
    = NotAuthorized
    | Retryable (Cmd Msg)
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
    | Retry (Cmd Msg)


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


viewToast : Toast.Info Toast -> List (Html Msg)
viewToast toastInfo =
    case toastInfo.content of
        NotAuthorized ->
            [ p [] [ text "You're no longer logged in" ]
            , a [ href (Router.buildFromTarget Router.Login), class "button" ] [ text "Log In Again" ]
            ]

        Retryable r ->
            [ p []
                [ text "There was a hiccup editing an event" ]
            , button [ onClick (Retry r) ] [ text "Retry" ]
            ]

        Unknown ->
            [ text "something went wrong editing an event" ]


type alias Interface base model msg =
    { base
        | localUpdate : Updater Model Msg -> Updater model msg
        , sendToast : Toast -> Updater model msg
        , lowerModel : model -> Model
    }


updaters : Interface base model msg -> Msg -> UpdateList model msg
updaters iface msg =
    let
        { localUpdate } =
            iface

        updateRes f =
            [ localUpdate (\m -> ( { m | resource = f m.resource }, Cmd.none )) ]
    in
    case msg of
        Entered creds loc ->
            case loc of
                None ->
                    [ localUpdate (\m -> ( { m | creds = creds }, getCurrentTime )) ]

                -- creating a new Event
                Nickname id ->
                    let
                        fetch =
                            fetchByNick creds id
                    in
                    [ localUpdate (\m -> ( { m | creds = creds, retry = Just fetch }, fetch ))
                    ]

                Url url ->
                    let
                        fetch =
                            fetchFromUrl creds url
                    in
                    [ localUpdate (\m -> ( { m | creds = creds, retry = Just fetch }, fetch ))
                    ]

        TimeNow t ->
            updateRes (\r -> { r | time = t })

        ChangeName n ->
            updateRes (\r -> { r | name = n })

        ChangeTime t ->
            case Iso8601.toTime t of
                Ok nt ->
                    updateRes (\r -> { r | time = nt })

                -- XXX error handling
                Err _ ->
                    []

        ChangeLocation l ->
            updateRes (\r -> { r | location = l })

        -- XXX
        Submit ->
            [ localUpdate
                (\m ->
                    let
                        put =
                            putEvent m.creds m
                    in
                    ( { m | retry = Just put }, put )
                )
            ]

        GotEvent etag ev ->
            [ localUpdate (\m -> ( { m | etag = etag, resource = ev, retry = Nothing }, Cmd.none )) ]

        -- XXX error handling
        ErrGetEvent err ->
            handleError iface err

        Retry cmd ->
            [ localUpdate (\m -> ( m, cmd )) ]


handleError : { a | sendToast : Toast -> Updater model msg, lowerModel : model -> Model } -> Error -> UpdateList model msg
handleError { sendToast, lowerModel } err =
    let
        maybeRetry m =
            case (lowerModel m).retry of
                Just r ->
                    sendToast (Retryable r) m

                Nothing ->
                    sendToast Unknown m
    in
    case err of
        Timeout ->
            [ maybeRetry ]

        NetworkError ->
            [ maybeRetry ]

        BadUrl _ ->
            [ sendToast Unknown ]

        BadStatus status ->
            case status of
                403 ->
                    [ sendToast NotAuthorized ]

                _ ->
                    [ sendToast Unknown ]

        BadBody _ ->
            [ sendToast Unknown ]


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
                , creds = creds -- Auth.Cred
                }

        Nothing ->
            Cmd.none


fetchByNick : Auth.Cred -> Int -> Cmd Msg
fetchByNick creds id =
    Up.retrieve
        { creds = creds
        , decoder = decoder
        , resMsg = resultDispatch ErrGetEvent (\( etag, ps ) -> GotEvent etag ps)
        , startAt = apiRoot
        , browsePlan = browseToEvent (nickToVars id)
        }


fetchFromUrl : Auth.Cred -> HM.Uri -> Cmd Msg
fetchFromUrl creds url =
    Up.retrieve
        { creds = creds
        , decoder = decoder

        -- XXX used to update path with stuff
        , resMsg = resultDispatch ErrGetEvent (\( etag, ps ) -> GotEvent etag ps)
        , startAt = HM.link HM.GET url
        , browsePlan = []
        }
