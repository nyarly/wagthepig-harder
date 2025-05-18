module EventEdit exposing
    ( Bookmark(..)
    , Model
    , Msg(..)
    , forCreate
    , init
    , updaters
    , view
    )

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
import ResourceUpdate as Up exposing (apiRoot, resultDispatch)
import Task
import Time
import Updaters exposing (UpdateList, Updater)
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
    | GotEvent Up.Etag Resource
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


type alias Interface base model msg =
    { base
        | localUpdate : Updater Model Msg -> Updater model msg
    }


updaters : Interface base model msg -> Msg -> UpdateList model msg
updaters { localUpdate } msg =
    let
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
                    [ localUpdate (\m -> ( { m | creds = creds }, fetchByNick creds id )) ]

                Url url ->
                    [ localUpdate (\m -> ( { m | creds = creds }, fetchFromUrl creds url )) ]

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

        GotEvent etag ev ->
            [ localUpdate (\m -> ( { m | etag = etag, resource = ev }, Cmd.none )) ]

        -- XXX error handling
        ErrGetEvent _ ->
            []

        -- XXX
        Submit ->
            [ localUpdate (\m -> ( m, putEvent m.creds m )) ]


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
