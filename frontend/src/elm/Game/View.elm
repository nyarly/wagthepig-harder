module Game.View exposing
    ( Game
    , GameAndSearch
    , Msg(..)
    , Nick
    , bggLink
    , bidiupdate
    , decoder
    , encoder
    , init
    , nickDecode
    , view
    )

import BGGAPI exposing (BGGGame(..), BGGThing, requestBGGItem, requestBGGSearch)
import Html exposing (Html, a, button, img, table, tbody, td, text, th, thead, tr)
import Html.Attributes exposing (disabled, href, name, src, type_)
import Html.Events exposing (onClick)
import Html.Extra as HtmlExtra
import Hypermedia exposing (Method(..), OperationSelector(..))
import Json.Decode as D
import Json.Decode.Pipeline exposing (optional)
import Json.Encode as E
import Maybe exposing (withDefault)
import OutMsg
import ViewUtil as Eww



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
-- Further thinking: original: Default v | Server v, updated: Maybe v
-- IOW: we used a default value, or the backend provided a value;
-- the user hasn't/has updated that with v.
-- the v is valid...? Always trust original values?
-- or Default v | Server v | DefaultUpdated v, v | ServerUpdated v, v
--
-- Original v = Default v | Server v
-- Value v = IsOriginal Original v | IsUpdated Original v, v
--
-- That then would mean either at the encode or put phases,
-- we could check the validity of our models,
-- knowing e.g. that our Default isn't allowed by the server,
-- trusting Original/Server values implicitly,
-- validating User input
-- XXX c&p from EventShow
{-
   , id : Maybe Affordance
   , update : Maybe Affordance
   , template : Maybe Affordance
   , nick : Nick
        |> custom (D.map (\u -> Just (HM.link GET u)) (D.field "id" D.string))
        |> custom (D.map (HM.selectAffordance (ByType "UpdateAction")) HM.affordanceListDecoder)
        |> custom (D.map (HM.selectAffordance (ByType "FindAction")) HM.affordanceListDecoder)
        |> required "nick" nickDecode
-}


type alias Game =
    { name : Maybe String
    , minPlayers : Maybe Int
    , maxPlayers : Maybe Int
    , durationSecs : Maybe Int
    , bggID : Maybe String
    , pitch : Maybe String
    , interested : Maybe Bool
    , canTeach : Maybe Bool
    , notes : Maybe String
    }


type alias Nick =
    { game_id : Int
    , user_id : String
    }


type alias GameAndSearch gas =
    { gas | resource : Game, bggSearchResults : List BGGGame }


init : Game
init =
    Game
        Nothing
        Nothing
        Nothing
        Nothing
        Nothing
        Nothing
        Nothing
        Nothing
        Nothing


decoder : D.Decoder Game
decoder =
    D.succeed Game
        |> decodeMaybe "name" D.string
        |> decodeMaybe "minPlayers" D.int
        |> decodeMaybe "maxPlayers" D.int
        |> decodeMaybe "durationSecs" D.int
        |> decodeMaybe "bggId" D.string
        |> decodeMaybe "pitch" D.string
        |> decodeMaybe "interested" D.bool
        |> decodeMaybe "canTeach" D.bool
        |> decodeMaybe "notes" D.string


nickDecode : D.Decoder Nick
nickDecode =
    D.map2 Nick
        (D.field "game_id" D.int)
        (D.field "user_id" D.string)


decodeMaybe : String -> D.Decoder a -> D.Decoder (Maybe a -> b) -> D.Decoder b
decodeMaybe name dec =
    optional name (D.map Just dec) Nothing


encoder : Game -> E.Value
encoder g =
    E.object
        [ ( "name", encodeMaybe E.string g.name )
        , ( "minPlayers", encodeMaybe E.int g.minPlayers )
        , ( "maxPlayers", encodeMaybe E.int g.maxPlayers )
        , ( "durationSecs", encodeMaybe E.int g.durationSecs )
        , ( "bggId", encodeMaybe E.string g.bggID )
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


type Msg
    = ChangeName String
    | ChangeMinPlayers Int
    | ChangeMaxPlayers Int
    | ChangeDurationSecs Int
    | ChangeBggID String
    | ChangePitch String
    | ChangeInterested Bool
    | ChangeCanTeach Bool
    | ChangeNotes String
    | Pick BGGThing
    | SearchName
    | BGGSearchResult (Result BGGAPI.Error (List BGGGame))
    | BGGThingResult (Result BGGAPI.Error BGGThing)



-- XXX this should be editView, and there should also be showView


view : Bool -> GameAndSearch gas -> List (Html Msg)
view showInterest model =
    let
        game =
            model.resource

        foundGames =
            model.bggSearchResults

        numMsg msg v =
            msg (withDefault 0 (String.toInt v))

        dstr =
            withDefault ""

        dnum =
            withDefault 0
    in
    [ Eww.inputPair [] "Name" (dstr game.name) ChangeName
    , button [ type_ "button", onClick SearchName, Eww.disabledMaybe game.name ] [ text "Search" ]
    , searchResults foundGames
    , Eww.inputPair [] "MinPlayers" (String.fromInt (dnum game.minPlayers)) (numMsg ChangeMinPlayers)
    , Eww.inputPair [] "MaxPlayers" (String.fromInt (dnum game.maxPlayers)) (numMsg ChangeMaxPlayers)
    , Eww.inputPair [] "DurationSecs" (String.fromInt (dnum game.durationSecs)) (numMsg ChangeDurationSecs)
    , Eww.inputPair [] "BggID" (dstr game.bggID) ChangeBggID
    , Eww.inputPair [] "Pitch" (dstr game.pitch) ChangePitch
    , interestedInput showInterest game
    , Eww.checkbox [] "CanTeach" (withDefault False game.canTeach) ChangeCanTeach
    , Eww.inputPair [] "Notes" (dstr game.notes) ChangeNotes
    ]


bggLink : { game | name : Maybe String, bggID : Maybe String } -> Html msg
bggLink { name, bggID } =
    let
        nameHTML =
            text (Maybe.withDefault "(name missing)" name)

        makeLink id =
            a [ href ("https://boardgamegeek.com/boardgame/" ++ id) ] [ nameHTML ]
    in
    Maybe.withDefault nameHTML (Maybe.map makeLink bggID)


searchResults : List BGGGame -> Html Msg
searchResults bggSearchResults =
    if List.length bggSearchResults > 0 then
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
                    bggSearchResults
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


interestedInput : Bool -> Game -> Html Msg
interestedInput showInterest g =
    if showInterest then
        Eww.checkbox [] "Interested" (withDefault False g.interested) ChangeInterested

    else
        HtmlExtra.nothing


gameUpdate : Msg -> Game -> ( Game, Cmd Msg )
gameUpdate msg game =
    case msg of
        ChangeName n ->
            ( { game | name = Just n }, Cmd.none )

        ChangeMinPlayers v ->
            ( { game | minPlayers = Just v }, Cmd.none )

        ChangeMaxPlayers v ->
            ( { game | maxPlayers = Just v }, Cmd.none )

        ChangeDurationSecs l ->
            ( { game | durationSecs = Just l }, Cmd.none )

        ChangeBggID i ->
            ( { game | bggID = Just i }, Cmd.none )

        ChangePitch p ->
            ( { game | pitch = Just p }, Cmd.none )

        ChangeInterested i ->
            ( { game | interested = Just i }, Cmd.none )

        ChangeCanTeach t ->
            ( { game | canTeach = Just t }, Cmd.none )

        ChangeNotes n ->
            ( { game | notes = Just n }, Cmd.none )

        Pick thing ->
            ( { game
                | name = Just thing.name
                , bggID = Just (String.fromInt thing.bggId)
                , minPlayers = Just thing.minPlayers
                , maxPlayers = Just thing.maxPlayers
                , durationSecs = Just (thing.durationMinutes * 60)
              }
            , Cmd.none
            )

        _ ->
            ( game, Cmd.none )


searchUpdate : Msg -> List BGGGame -> ( List BGGGame, Cmd Msg )
searchUpdate msg bggSearchResults =
    case msg of
        Pick thing ->
            let
                onlyPicked g =
                    case g of
                        SearchResult _ ->
                            False

                        Thing t ->
                            t.bggId == thing.bggId
            in
            ( List.filter onlyPicked bggSearchResults, Cmd.none )

        BGGSearchResult r ->
            case r of
                Ok l ->
                    ( l, shotgunGames l )

                Err _ ->
                    ( bggSearchResults, Cmd.none )

        BGGThingResult r ->
            case r of
                Ok newGame ->
                    ( enrichGame bggSearchResults newGame, Cmd.none )

                Err _ ->
                    ( bggSearchResults, Cmd.none )

        _ ->
            ( bggSearchResults, Cmd.none )


bidiupdate : Msg -> GameAndSearch g -> ( GameAndSearch g, Cmd Msg, OutMsg.Msg )
bidiupdate msg model =
    let
        gameDispatch =
            let
                ( game, out ) =
                    gameUpdate msg model.resource
            in
            ( { model | resource = game }, out, OutMsg.None )

        searchDispatch =
            let
                ( search, out ) =
                    searchUpdate msg model.bggSearchResults
            in
            ( { model | bggSearchResults = search }, out, OutMsg.None )
    in
    case msg of
        ChangeName _ ->
            gameDispatch

        ChangeMinPlayers _ ->
            gameDispatch

        ChangeMaxPlayers _ ->
            gameDispatch

        ChangeDurationSecs _ ->
            gameDispatch

        ChangeBggID _ ->
            gameDispatch

        ChangePitch _ ->
            gameDispatch

        ChangeInterested _ ->
            gameDispatch

        ChangeCanTeach _ ->
            gameDispatch

        ChangeNotes _ ->
            gameDispatch

        BGGSearchResult _ ->
            searchDispatch

        BGGThingResult _ ->
            searchDispatch

        Pick _ ->
            let
                ( game, gOut ) =
                    gameUpdate msg model.resource

                ( search, sOut ) =
                    searchUpdate msg model.bggSearchResults
            in
            ( { model | resource = game, bggSearchResults = search }, Cmd.batch [ gOut, sOut ], OutMsg.None )

        SearchName ->
            ( model, requestBGGSearch BGGSearchResult (withDefault "" model.resource.name), OutMsg.None )


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
