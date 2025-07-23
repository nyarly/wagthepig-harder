module WhatShouldWePlay exposing
    ( EventPlayers
    , Interface
    , Model
    , Msg(..)
    , Nick
    , Recco
    , ReccoSorting
    , Toast
    , init
    , updaters
    , view
    , viewToast
    )

import Auth
import BGGAPI
import Dict
import Event exposing (browseToEvent)
import Html exposing (Html, a, button, div, form, h1, h3, img, label, li, option, p, select, span, table, td, text, th, thead, tr, ul)
import Html.Attributes exposing (class, for, href, multiple, src, type_, value)
import Html.Events exposing (onClick, onSubmit)
import Html.Keyed as Keyed
import Http exposing (Error)
import Hypermedia as HM exposing (Affordance, Method(..), OperationSelector(..), Response, Uri, decodeMaybe)
import Json.Decode as D
import Json.Decode.Pipeline exposing (custom, hardcoded, required)
import Json.Encode as E
import Players exposing (OtherPlayers(..), Player, closeOtherPlayers, otherPlayersDecoder, playerDecoder, playerName)
import ResourceUpdate exposing (apiRoot, resultDispatch, retrieve, taggedResultDispatch, update)
import Router exposing (ReccoSortBy(..))
import TableSort exposing (SortOrder(..), compareMaybes)
import Toast
import Updaters exposing (Tried, Updater, noChange)
import ViewUtil as Ew


type alias Model =
    { creds : Auth.Cred
    , nick : Nick
    , players : EventPlayers
    , selectedIds : List String
    , extraCount : Int
    , suggestion : Maybe (List Recco)
    , retry : Maybe (Tried Msg Nick)
    }


type alias Recco =
    { name : Maybe String
    , userLink : Affordance
    , minPlayers : Maybe Int
    , maxPlayers : Maybe Int
    , durationSecs : Maybe Int
    , bggId : Maybe String
    , interestLevel : Int
    , teachers : Int
    , whoElse : OtherPlayers
    , thumbnail : Maybe String
    }


requestEncoder : Model -> E.Value
requestEncoder model =
    let
        playerIds =
            case model.players of
                Just ps ->
                    let
                        ( me, _ ) =
                            meAndThem model.creds ps
                    in
                    case me of
                        Just thisPlayer ->
                            thisPlayer.id :: model.selectedIds

                        Nothing ->
                            model.selectedIds

                Nothing ->
                    model.selectedIds
    in
    E.object
        [ ( "players", E.list E.string playerIds )
        , ( "extraPlayers", E.int model.extraCount )
        ]


reccoListDecoder : D.Decoder (List Recco)
reccoListDecoder =
    D.field "games" (D.list reccoDecoder)


reccoDecoder : D.Decoder Recco
reccoDecoder =
    D.succeed Recco
        |> decodeMaybe "name" D.string
        |> custom (D.map (HM.link GET) (D.at [ "users", "id" ] D.string))
        |> decodeMaybe "minPlayers" D.int
        |> decodeMaybe "maxPlayers" D.int
        |> decodeMaybe "durationSecs" D.int
        |> decodeMaybe "bggId" D.string
        |> required "interestLevel" D.int
        |> required "teachers" D.int
        |> hardcoded Empty
        |> hardcoded Nothing


type alias ReccoSorting =
    TableSort.Sorting ReccoSortBy


type Msg
    = Entered Auth.Cred Nick
    | SelectUsers (List String)
    | SetExtraPlayerCount Int
    | ChangeSort ReccoSorting
    | ClearReccos
    | Submit
    | GotRecco (List Recco)
    | GetOtherPlayers Affordance
    | GotOtherPlayers Uri OtherPlayers
    | GotBGGData Uri String
    | ErrGetBGGData BGGAPI.Error
    | CloseOtherPlayers Uri
    | ErrOtherPlayers HM.Error
    | ErrGetRecco HM.Error
    | GotPlayers (List Player)
    | ErrGetPlayers HM.Error
    | Retry Msg


type Toast
    = Retryable (Tried Msg Nick)
    | Unknown


type alias Nick =
    { eventId : Int
    }


init : Model
init =
    Model
        Auth.unauthenticated
        (Nick 0)
        Nothing
        []
        0
        Nothing
        Nothing


type alias EventPlayers =
    Maybe (List Player)


type alias Interface base model msg =
    { base
        | localUpdate : Updater Model Msg -> Updater model msg
        , requestUpdatePath : Router.Target -> Updater model msg
        , lowerModel : model -> Model
        , handleErrorWithRetry : Updater model msg -> Error -> Updater model msg
        , sendToast : Toast -> Updater model msg
    }


updaters : Interface base model msg -> Msg -> Updater model msg
updaters ({ localUpdate, requestUpdatePath, lowerModel, handleErrorWithRetry, sendToast } as iface) msg =
    let
        closeRecco recco =
            { recco | whoElse = closeOtherPlayers recco.whoElse }

        closeAll reccos =
            Maybe.map (List.map closeRecco) reccos

        justTried model =
            Just (Tried msg model.nick)
    in
    case msg of
        Entered creds nick ->
            let
                fetchUpdater m =
                    ( { m | creds = creds, nick = nick, retry = Just (Tried (Entered creds nick) nick) }
                    , fetchEventPlayers creds nick
                    )

                retryUpdater m =
                    ( { m | creds = creds }, Cmd.none )
            in
            Updaters.entryUpdater iface fetchUpdater retryUpdater updaters nick

        SelectUsers selectedIds ->
            localUpdate (\m -> ( { m | selectedIds = selectedIds }, Cmd.none ))

        SetExtraPlayerCount extraCount ->
            localUpdate (\m -> ( { m | extraCount = extraCount }, Cmd.none ))

        GotRecco suggestion ->
            localUpdate (\m -> ( { m | suggestion = Just suggestion, retry = justTried m }, bggGameData suggestion ))

        Submit ->
            localUpdate (\m -> ( m, sendRequest m ))

        ClearReccos ->
            localUpdate (\m -> ( { m | suggestion = Nothing }, Cmd.none ))

        ChangeSort newsort ->
            \m -> requestUpdatePath (Router.WhatShouldWePlay (lowerModel m).nick.eventId (Just newsort)) m

        CloseOtherPlayers url ->
            localUpdate (\m -> ( { m | suggestion = reccoItemUpdate url closeRecco m.suggestion }, Cmd.none ))

        GotPlayers players ->
            localUpdate (\m -> ( { m | players = Just players, retry = Nothing }, Cmd.none ))

        GetOtherPlayers aff ->
            localUpdate (\m -> ( { m | suggestion = closeAll m.suggestion, retry = justTried m }, fetchOtherPlayers m.creds aff ))

        GotOtherPlayers uri list ->
            localUpdate
                (\m ->
                    ( { m
                        | suggestion =
                            reccoItemUpdate uri (\g -> { g | whoElse = list }) m.suggestion
                        , retry = Nothing
                      }
                    , Cmd.none
                    )
                )

        GotBGGData url thumbnail ->
            localUpdate
                (\m ->
                    ( { m
                        | suggestion =
                            reccoItemUpdate url (\g -> { g | thumbnail = Just thumbnail }) m.suggestion
                        , retry = Nothing
                      }
                    , Cmd.none
                    )
                )

        ErrGetRecco err ->
            handleErrorWithRetry (maybeRetry iface) err

        ErrGetPlayers err ->
            handleErrorWithRetry (maybeRetry iface) err

        ErrOtherPlayers err ->
            handleErrorWithRetry (maybeRetry iface) err

        ErrGetBGGData _ ->
            \model ->
                let
                    toast =
                        case (lowerModel model).retry of
                            Just r ->
                                Retryable r

                            Nothing ->
                                Unknown
                in
                sendToast toast model

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


reccoItemUpdate : Uri -> (Recco -> Recco) -> Maybe (List Recco) -> Maybe (List Recco)
reccoItemUpdate uri doUpdate reccos =
    Maybe.map
        (List.map
            (\r ->
                if r.userLink.uri == uri then
                    doUpdate r

                else
                    r
            )
        )
        reccos


meAndThem : Auth.Cred -> List Player -> ( Maybe Player, List Player )
meAndThem creds users =
    let
        myEmail =
            Auth.accountID creds

        ( mes, them ) =
            List.partition (\u -> u.email == myEmail) users
    in
    ( List.head mes, them )


view : Model -> Maybe ReccoSorting -> List (Html Msg)
view model sorting =
    case model.suggestion of
        Nothing ->
            paramsView model

        Just suggs ->
            reccoView model suggs sorting


viewToast : Toast.Info Toast -> List (Html Msg)
viewToast toastInfo =
    case toastInfo.content of
        Retryable r ->
            [ p []
                [ text "There was a hiccup getting reccomendations" ]
            , button [ onClick (Retry r.msg) ] [ text "Retry" ]
            ]

        Unknown ->
            [ text "something weird went wrong getting reccomendations" ]


paramsView : Model -> List (Html Msg)
paramsView model =
    [ h1 [] [ text "Find a game" ]
    , p [] [ text "We'll list games based on how many folks you indicate are listed, and have capacity for everyone." ]
    , p [] [ text "Select the players on the list you'd like to play with. If there's other folks in the group, add a headcount of extra." ]
    , form [ onSubmit Submit ]
        [ div [ class "field" ]
            [ label [ for "suggestion_users" ] [ text "Other Players" ]
            , case model.players of
                Nothing ->
                    text "(fetching)"

                Just players ->
                    let
                        ( me, them ) =
                            meAndThem model.creds players
                    in
                    div []
                        [ text (Maybe.withDefault "you" (Maybe.map playerName me) ++ " and...")
                        , select [ multiple True, Ew.onSelection SelectUsers ] (List.map (\p -> option [ value p.id ] [ text (playerName p) ]) them)
                        ]
            ]
        , Ew.inputPair [ type_ "number" ] "Extra Players" (String.fromInt model.extraCount) (\n -> SetExtraPlayerCount (Maybe.withDefault 0 (String.toInt n)))
        , button [] [ text "Let's Play!" ]
        ]
    ]


sortDefault : Maybe ( ReccoSortBy, SortOrder ) -> ( ReccoSortBy, SortOrder )
sortDefault =
    Maybe.withDefault ( ReccoName, Descending )


sortWith : ReccoSortBy -> Recco -> Recco -> Order
sortWith by l r =
    let
        cmpM f =
            compareMaybes (f l) (f r)

        cmp f =
            compare (f l) (f r)
    in
    case by of
        ReccoName ->
            cmpM .name

        Players ->
            case cmpM .maxPlayers of
                EQ ->
                    cmpM .minPlayers

                otherwise ->
                    otherwise

        Length ->
            cmpM .durationSecs

        PresentInterested ->
            cmp .interestLevel

        PresentTeachers ->
            cmp .teachers


reccoView : Model -> List Recco -> Maybe ( ReccoSortBy, SortOrder ) -> List (Html Msg)
reccoView model list maybeSort =
    let
        sorting =
            sortDefault maybeSort

        sortingHeader =
            TableSort.sortingHeader ChangeSort sorting

        sort l =
            TableSort.sort sortWith sorting l

        me =
            Maybe.map (meAndThem model.creds) model.players
                |> Maybe.andThen (\( m, _ ) -> m)

        activeIds =
            case me of
                Just i ->
                    i.id :: model.selectedIds

                Nothing ->
                    model.selectedIds

        activePlayers =
            case model.players of
                Just players ->
                    List.filter (\p -> List.member p.id activeIds) players

                Nothing ->
                    []

        playerNames =
            List.map playerName activePlayers

        playerJoined =
            case ( model.extraCount, playerNames ) of
                ( 0, [] ) ->
                    "nobody"

                ( 0, [ one ] ) ->
                    one

                ( 0, one :: rest ) ->
                    String.join "," rest ++ " and " ++ one

                ( 1, [] ) ->
                    "one player"

                ( n, [] ) ->
                    String.fromInt n ++ " players"

                ( n, rest ) ->
                    String.join "," rest ++ " and " ++ String.fromInt n ++ " more"
    in
    [ h1 [] [ text "Recommendations" ]
    , p [] [ text ("Games for " ++ playerJoined) ]
    , p []
        [ a
            [ class "button"
            , href <| Router.buildFromTarget <| Router.EventShow model.nick.eventId Nothing
            ]
            [ text "Back to the Event" ]
        , button [ onClick ClearReccos ] [ text "Revise Search" ]
        ]
    , table []
        [ thead []
            [ th [] []
            , sortingHeader "Name" [ class "name" ] ReccoName
            , sortingHeader "Players" [ class "players" ] Players
            , sortingHeader "Length" [ class "length" ] Length
            , sortingHeader "Interested" [ class "interested" ] PresentInterested
            , sortingHeader "Teachers" [ class "teachers" ] PresentTeachers
            , th [ class "whoelse" ] []
            ]
        , Keyed.node "tbody" [] (List.map makeReccoRow (sort list))
        ]
    ]


makeReccoRow : Recco -> ( String, Html Msg )
makeReccoRow recco =
    let
        sdef =
            Maybe.withDefault ""

        ndef =
            Maybe.withDefault 0

        nsdef mi =
            String.fromInt <| Maybe.withDefault 0 mi
    in
    ( recco.userLink.uri
    , tr []
        [ td [ class "image" ]
            (case recco.thumbnail of
                Just th ->
                    [ img [ src th ] [] ]

                Nothing ->
                    []
            )
        , td [ class "name" ] [ text <| sdef recco.name ]
        , td [ class "players" ] [ text (nsdef recco.minPlayers ++ "-" ++ nsdef recco.maxPlayers) ]
        , td [ class "length" ] [ text <| String.fromFloat ((toFloat <| ndef recco.durationSecs) / 60) ]
        , td [ class "interested" ] [ text <| String.fromInt recco.interestLevel ]
        , td [ class "teachers" ] [ text <| String.fromInt recco.teachers ]
        , td [ class "whoelse-button" ]
            [ button [ class "whoelse", onClick (GetOtherPlayers recco.userLink) ] [ span [] [ text "Who Else?" ] ]
            ]
        , whoElseTD recco
        ]
    )


whoElseTD : Recco -> Html Msg
whoElseTD { whoElse, userLink, name } =
    case whoElse of
        Open list ->
            td [ class "whoelse-list" ]
                [ h3 []
                    [ text ("Players interested in " ++ Maybe.withDefault "that game" name) ]
                , ul
                    []
                    (List.map
                        (\p -> li [] [ text (playerName p) ])
                        list
                    )
                , button [ class "close close-whoelse", onClick (CloseOtherPlayers userLink.uri) ] [ text "close" ]
                ]

        _ ->
            td [ class "empty whoelse" ] []


bggGameData : List Recco -> Cmd Msg
bggGameData list =
    let
        xform rec bggData =
            GotBGGData rec.userLink.uri bggData.thumbnail
    in
    BGGAPI.shotgunGames .bggId (taggedResultDispatch (\_ -> ErrGetBGGData) xform) list


browseToPost : HM.TemplateVars -> List (Response -> Result String Affordance)
browseToPost vars =
    [ HM.browse [ "events" ] (ByType "ViewAction")
    , HM.browse [ "eventById" ] (ByType "FindAction") |> HM.fillIn vars
    , HM.browse [ "games" ] (ByType "FindAction") |> HM.fillIn vars
    , HM.browse [ "makeRecommendation" ] (ByType "PlayAction")
    ]


nickToVars : Auth.Cred -> Nick -> Dict.Dict String String
nickToVars creds nick =
    Dict.fromList
        [ ( "event_id", String.fromInt nick.eventId )
        , ( "user_id", Auth.accountID creds )
        ]


fetchEventPlayers : Auth.Cred -> Nick -> Cmd Msg
fetchEventPlayers creds nick =
    let
        vars =
            Dict.fromList [ ( "event_id", String.fromInt nick.eventId ) ]
    in
    retrieve
        { headers = Auth.credHeader creds
        , decoder = D.field "users" (D.list playerDecoder)
        , resMsg = resultDispatch ErrGetPlayers (\( _, ps ) -> GotPlayers ps)
        , startAt = apiRoot
        , browsePlan = browseToEvent vars ++ [ HM.browse [ "users" ] (ByType "ViewAction") ]
        }


sendRequest : Model -> Cmd Msg
sendRequest model =
    update
        { resource = model
        , etag = Nothing
        , encode = requestEncoder
        , decoder = reccoListDecoder
        , resMsg = resultDispatch ErrGetRecco (\( _, r ) -> GotRecco r)
        , startAt = apiRoot
        , browsePlan = browseToPost (nickToVars model.creds model.nick)
        , headers = Auth.credHeader model.creds
        }


fetchOtherPlayers : Auth.Cred -> Affordance -> Cmd Msg
fetchOtherPlayers creds from =
    retrieve
        { headers = Auth.credHeader creds
        , decoder = otherPlayersDecoder
        , resMsg = resultDispatch ErrOtherPlayers (\( _, o ) -> GotOtherPlayers from.uri o)
        , startAt = from
        , browsePlan = []
        }
