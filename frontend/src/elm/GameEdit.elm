module GameEdit exposing (..)

import Auth
import BGGAPI exposing (BGGGame(..), BGGThing, requestBGGItem, requestBGGSearch)
import Dict
import Html exposing (Html, a, button, div, form, img, table, tbody, td, text, th, thead, tr)
import Html.Attributes exposing (class, disabled, href, name, src, type_)
import Html.Attributes.Extra as Attr
import Html.Events exposing (onClick, onSubmit)
import Html.Extra as HtmlExtra
import Hypermedia as HM exposing (Affordance, Method(..), OperationSelector(..), Response)
import Json.Decode as D
import Json.Decode.Pipeline exposing (custom, optional)
import Json.Encode as E
import Maybe exposing (withDefault)
import OutMsg
import ResourceUpdate as Up
import Router
import ViewUtil as Eww


type alias EventId =
    Int


type alias GameId =
    Int


type alias Model =
    { creds : Auth.Cred
    , etag : Up.Etag
    , event_id : EventId
    , id : Maybe GameId
    , bggSearchResults : List BGGGame
    , resource : Game -- XXX Maybe?
    }



-- XXX There's a general pattern to note:
-- we sometimes have proposed vs. accepted resources
-- a proposed resource (e.g. during create) doesn't have a URL yet
-- and there's the larger issue of the gradual transition from nothing to a valid resource
-- (i.e. at 0% we have no user input, and at 100% we have something we might be able to POST)
-- likewise, there's the interesting distinction between a Show, where we Maybe have the resource,
-- but if so it will be fully formed and a Create where we definitely have a resource that might be 0%.
--
-- Considering: a (Resource)Field type, as Server|User|Unset. "encodeField" and "decodeField"
-- (like the maybe versions here). Would also begin support for smart 409 resolution
-- also helps with client-side validation, since you only consider fields that are User
--
-- XXX c&p from EventShow


type alias Game =
    { id : Maybe Affordance
    , update : Maybe Affordance
    , template : Maybe Affordance
    , nick : Maybe Nick
    , name : Maybe String
    , minPlayers : Maybe Int
    , maxPlayers : Maybe Int
    , bggLink : Maybe String
    , durationSecs : Maybe Int
    , bggID : Maybe String
    , pitch : Maybe String
    , interested : Maybe Bool
    , canTeach : Maybe Bool
    , notes : Maybe String
    }


type alias Nick =
    { game_id : Int
    }


decoder : D.Decoder Game
decoder =
    D.succeed Game
        |> custom (D.map (\u -> Just (HM.link GET u)) (D.field "id" D.string))
        |> custom (D.map (HM.selectAffordance (ByType "UpdateAction")) HM.affordanceListDecoder)
        |> custom (D.map (HM.selectAffordance (ByType "FindAction")) HM.affordanceListDecoder)
        |> decodeMaybe "nick" nickDecode
        |> decodeMaybe "name" D.string
        |> decodeMaybe "minPlayers" D.int
        |> decodeMaybe "maxPlayers" D.int
        |> decodeMaybe "bggLink" D.string
        |> decodeMaybe "durationSecs" D.int
        |> decodeMaybe "bggId" D.string
        |> decodeMaybe "pitch" D.string
        |> decodeMaybe "interested" D.bool
        |> decodeMaybe "canTeach" D.bool
        |> decodeMaybe "notes" D.string


nickDecode : D.Decoder Nick
nickDecode =
    D.map Nick (D.field "game_id" D.int)


decodeMaybe : String -> D.Decoder a -> D.Decoder (Maybe a -> b) -> D.Decoder b
decodeMaybe name dec =
    optional name (D.map Just dec) Nothing


encoder : Game -> E.Value
encoder g =
    E.object
        [ ( "name", encodeMaybe E.string g.name )
        , ( "minPlayers", encodeMaybe E.int g.minPlayers )
        , ( "maxPlayers", encodeMaybe E.int g.maxPlayers )
        , ( "bggLink", encodeMaybe E.string g.bggLink )
        , ( "durationSecs", encodeMaybe E.int g.durationSecs )
        , ( "bggID", encodeMaybe E.string g.bggID )
        , ( "pitch", encodeMaybe E.string g.pitch )
        , ( "interested", encodeMaybe E.bool g.interested )
        , ( "canTeach", encodeMaybe E.bool g.canTeach )
        , ( "notes", encodeMaybe E.string g.notes )
        ]


encodeMaybe : (a -> E.Value) -> Maybe a -> E.Value
encodeMaybe enc ma =
    case ma of
        Just a ->
            enc a

        Nothing ->
            E.null


type Bookmark
    = None
    | New Affordance
    | Nickname Nick
    | Url HM.Uri


type Msg
    = ForCreate Auth.Cred EventId
    | ForEdit Auth.Cred EventId GameId
    | LoadLoc Affordance
    | ChangeName String
    | ChangeMinPlayers Int
    | ChangeMaxPlayers Int
    | ChangeBggLink String
    | ChangeDurationSecs Int
    | ChangeBggID String
    | ChangePitch String
    | ChangeInterested Bool
    | ChangeCanTeach Bool
    | ChangeNotes String
    | Pick BGGThing
    | SearchName
    | Submit
    | CreatedGame
    | GotGame Up.Etag Game OutMsg.Msg
    | BGGSearchResult (Result BGGAPI.Error (List BGGGame))
    | BGGThingResult (Result BGGAPI.Error BGGThing)
    | ErrGetGame HM.Error


init : Model
init =
    Model
        Auth.unauthenticated
        Nothing
        0
        Nothing
        []
        (Game
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
        )


view : Model -> List (Html Msg)
view model =
    let
        g =
            model.resource

        qstr =
            withDefault ""

        qnum =
            withDefault 0

        numMsg msg v =
            msg (withDefault 0 (String.toInt v))
    in
    [ a [ href (Router.buildFromTarget (Router.EventShow model.event_id)) ] [ text "Back to Event" ]
    , form [ onSubmit Submit ]
        [ Eww.inputPair [] "Name" (qstr g.name) ChangeName
        , button [ type_ "button", onClick SearchName, Eww.disabledUnless model.resource.name ] [ text "Search" ]
        , searchResults model
        , Eww.inputPair [] "MinPlayers" (String.fromInt (qnum g.minPlayers)) (numMsg ChangeMinPlayers)
        , Eww.inputPair [] "MaxPlayers" (String.fromInt (qnum g.maxPlayers)) (numMsg ChangeMaxPlayers)
        , Eww.inputPair [] "DurationSecs" (String.fromInt (qnum g.durationSecs)) (numMsg ChangeDurationSecs)
        , Eww.inputPair [] "BggLink" (qstr g.bggLink) ChangeBggLink
        , Eww.inputPair [] "BggID" (qstr g.bggID) ChangeBggID
        , Eww.inputPair [] "Pitch" (qstr g.pitch) ChangePitch
        , interestedInput model.id g
        , Eww.checkbox [] "CanTeach" (withDefault False g.canTeach) ChangeCanTeach
        , Eww.inputPair [] "Notes" (qstr g.notes) ChangeNotes
        , div [ class "actions" ]
            [ button
                [ case ( model.id, model.resource.update ) of
                    ( Nothing, _ ) ->
                        Attr.empty

                    ( Just _, Just _ ) ->
                        Attr.empty

                    ( Just _, Nothing ) ->
                        disabled True
                ]
                [ text "Submit" ]
            ]
        ]
    ]


searchResults : Model -> Html Msg
searchResults model =
    if List.length model.bggSearchResults > 0 then
        table []
            [ thead []
                [ th [] [ text "Thumb" ]
                , th [] [ text "Name" ]
                , th [] [ text "Description" ]
                , th [] [ text "Pick" ]
                ]
            , tbody []
                (List.map
                    viewBggResult
                    model.bggSearchResults
                )
            ]

    else
        HtmlExtra.nothing


viewBggResult : BGGGame -> Html Msg
viewBggResult game =
    case game of
        SearchResult bggRes ->
            tr []
                [ td [] [ text "placeholder" ]
                , td [] [ text bggRes.name ]
                , td [] [ text "?" ]
                , td [] [ button [ type_ "button", disabled True ] [ text "Pick" ] ]
                ]

        Thing thing ->
            tr []
                [ td [] [ img [ src thing.thumbnail ] [] ]
                , td [] [ text thing.name ]
                , td [] [ text thing.description ]
                , td [] [ button [ type_ "button", onClick (Pick thing) ] [ text "Pick" ] ]
                ]


interestedInput : Maybe Int -> Game -> Html Msg
interestedInput id g =
    case id of
        Just _ ->
            Eww.checkbox [] "Interested" (withDefault False g.interested) ChangeInterested

        Nothing ->
            HtmlExtra.nothing


bidiupdate : Msg -> Model -> ( Model, Cmd Msg, OutMsg.Msg )
bidiupdate msg model =
    let
        updateRes f m =
            { m | resource = f m.resource }
    in
    case msg of
        ForCreate creds ev ->
            ( { init | event_id = ev, creds = creds } |> updateRes (\r -> { r | interested = Just True }), Cmd.none, OutMsg.None )

        ForEdit creds ev i ->
            ( { init | event_id = ev, id = Just i, creds = creds }, fetchByNick creds ev (Nick i), OutMsg.None )

        LoadLoc aff ->
            ( model, fetchFromUrl model.creds model.event_id aff.uri, OutMsg.None )

        ChangeName n ->
            ( updateRes (\r -> { r | name = Just n }) model, Cmd.none, OutMsg.None )

        ChangeMinPlayers v ->
            ( updateRes (\r -> { r | minPlayers = Just v }) model, Cmd.none, OutMsg.None )

        ChangeMaxPlayers v ->
            ( updateRes (\r -> { r | maxPlayers = Just v }) model, Cmd.none, OutMsg.None )

        ChangeBggLink l ->
            ( updateRes (\r -> { r | bggLink = Just l }) model, Cmd.none, OutMsg.None )

        ChangeDurationSecs l ->
            ( updateRes (\r -> { r | durationSecs = Just l }) model, Cmd.none, OutMsg.None )

        ChangeBggID i ->
            ( updateRes (\r -> { r | bggID = Just i }) model, Cmd.none, OutMsg.None )

        ChangePitch p ->
            ( updateRes (\r -> { r | pitch = Just p }) model, Cmd.none, OutMsg.None )

        ChangeInterested i ->
            ( updateRes (\r -> { r | interested = Just i }) model, Cmd.none, OutMsg.None )

        ChangeCanTeach t ->
            ( updateRes (\r -> { r | canTeach = Just t }) model, Cmd.none, OutMsg.None )

        ChangeNotes n ->
            ( updateRes (\r -> { r | notes = Just n }) model, Cmd.none, OutMsg.None )

        Pick thing ->
            let
                res =
                    model.resource

                newRes =
                    { res
                        | name = Just thing.name
                        , bggID = Just (String.fromInt thing.bggId)
                        , minPlayers = Just thing.minPlayers
                        , maxPlayers = Just thing.maxPlayers
                        , durationSecs = Just (thing.durationMinutes * 60)
                    }

                onlyPicked g =
                    case g of
                        SearchResult _ ->
                            False

                        Thing t ->
                            t.bggId == thing.bggId
            in
            ( { model | resource = newRes, bggSearchResults = List.filter onlyPicked model.bggSearchResults }, Cmd.none, OutMsg.None )

        Submit ->
            ( model, putGame model.creds model, OutMsg.None )

        SearchName ->
            case model.resource.name of
                Just name ->
                    ( model, requestBGGSearch BGGSearchResult name, OutMsg.None )

                Nothing ->
                    ( model, Cmd.none, OutMsg.None )

        CreatedGame ->
            ( model, Cmd.none, OutMsg.Main (OutMsg.Nav (Router.EventShow model.event_id)) )

        GotGame etag g outmsg ->
            ( { model | etag = etag, resource = g }, Cmd.none, outmsg )

        BGGSearchResult r ->
            case r of
                Ok l ->
                    ( { model | bggSearchResults = l }, shotgunGames l, OutMsg.None )

                Err _ ->
                    ( model, Cmd.none, OutMsg.None )

        BGGThingResult r ->
            case r of
                Ok newGame ->
                    ( { model | bggSearchResults = enrichGame model.bggSearchResults newGame }, Cmd.none, OutMsg.None )

                Err _ ->
                    ( model, Cmd.none, OutMsg.None )

        ErrGetGame _ ->
            ( model, Cmd.none, OutMsg.None )


shotgunGames : List BGGGame -> Cmd Msg
shotgunGames list =
    let
        fetchFromSearch game =
            case game of
                SearchResult res ->
                    requestBGGItem BGGThingResult res.id

                _ ->
                    Cmd.none
    in
    Cmd.batch (List.map fetchFromSearch list)


enrichGame : List BGGGame -> BGGThing -> List BGGGame
enrichGame list newGame =
    let
        swapGame oldGame =
            case oldGame of
                SearchResult res ->
                    if res.id == newGame.bggId then
                        Thing newGame

                    else
                        oldGame

                _ ->
                    oldGame
    in
    List.map swapGame list


updateMsg : Up.Representation Game -> Msg
updateMsg ex =
    case ex of
        Up.Loc aff ->
            LoadLoc aff

        Up.Res etag res out ->
            GotGame etag res out

        Up.Error err ->
            ErrGetGame err


createMsg : Up.Representation Game -> Msg
createMsg ex =
    case ex of
        Up.Loc _ ->
            CreatedGame

        Up.Res _ _ _ ->
            CreatedGame

        Up.Error err ->
            ErrGetGame err


nickToVars : Auth.Cred -> Int -> Nick -> Dict.Dict String String
nickToVars cred event_id nick =
    Dict.fromList
        [ ( "event_id", String.fromInt event_id )
        , ( "user_id", Auth.accountID cred )
        , ( "game_id", String.fromInt nick.game_id )
        ]


browseToCreate : HM.TemplateVars -> List (Response -> Result String Affordance)
browseToCreate vars =
    [ HM.browse [ "events" ] (ByType "ViewAction")
    , HM.browse [ "eventById" ] (ByType "FindAction") |> HM.fillIn vars
    , HM.browse [ "games" ] (ByType "AddAction") |> HM.fillIn vars
    ]


browseToFetch : HM.TemplateVars -> List (Response -> Result String Affordance)
browseToFetch vars =
    [ HM.browse [ "events" ] (ByType "ViewAction")
    , HM.browse [ "eventById" ] (ByType "FindAction") |> HM.fillIn vars
    , HM.browse [ "games" ] (ByType "FindAction") |> HM.fillIn vars
    , HM.browse [ "game" ] (ByType "FindAction") |> HM.fillIn vars
    ]


putGame : Auth.Cred -> Model -> Cmd Msg
putGame creds model =
    case Debug.log "putGame" model.resource.id of
        Just _ ->
            Up.put encoder decoder updateMsg creds model.etag model.resource

        Nothing ->
            Up.browseToSend encoder decoder createMsg (nickToVars creds model.event_id) browseToCreate (Nick 0) creds model.resource


fetchByNick : Auth.Cred -> Int -> Nick -> Cmd Msg
fetchByNick creds event_id =
    Up.fetchByNick decoder updateMsg (nickToVars creds event_id) (Up.Browse browseToFetch) creds


fetchFromUrl : Auth.Cred -> Int -> HM.Uri -> Cmd Msg
fetchFromUrl creds event_id =
    let
        routeByHasNick r =
            let
                nick =
                    Maybe.withDefault (Nick 0) r.nick
            in
            Router.GameEdit event_id nick.game_id
    in
    Up.fetchFromUrl decoder updateMsg routeByHasNick creds
