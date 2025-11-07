module BGG exposing (SearchResult, Thing, fetchThingById, search, shotgunGames)

import Auth
import Dict
import Hypermedia as HM exposing (Affordance, Method(..), OperationSelector(..), Response, decodeMaybe)
import Json.Decode as D
import Json.Decode.Pipeline exposing (custom, required)
import ResourceUpdate as Up exposing (Etag, apiRoot)


type alias Thing =
    { bggId : String
    , kind : String
    , thumbnail : Maybe String
    , image : Maybe String
    , name : Maybe String
    , altnames : List String
    , description : Maybe String
    , yearPublished : Maybe Int
    , minPlayers : Maybe Int
    , maxPlayers : Maybe Int
    , minDuration : Maybe Int
    , maxDuration : Maybe Int
    , durationMinutes : Maybe Int
    }


thingDecoder : D.Decoder Thing
thingDecoder =
    D.succeed Thing
        |> required "bgg_id" D.string
        |> required "kind" D.string
        |> decodeMaybe "thumbnail" D.string
        |> decodeMaybe "image" D.string
        |> decodeMaybe "name" D.string
        |> required "altnames" (D.list D.string)
        |> decodeMaybe "description" D.string
        |> decodeMaybe "year_published" D.int
        |> decodeMaybe "min_players" D.int
        |> decodeMaybe "max_players" D.int
        |> decodeMaybe "min_duration" D.int
        |> decodeMaybe "max_duration" D.int
        |> decodeMaybe "duration" D.int


thingResponseDecoder : D.Decoder Thing
thingResponseDecoder =
    D.at [ "thing" ] thingDecoder


fetchThingById : Auth.Cred -> String -> (Result HM.Error ( Etag, Thing ) -> msg) -> Cmd msg
fetchThingById creds thing_id resultDispatch =
    let
        buildVars : String -> Dict.Dict String String
        buildVars id =
            Dict.fromList
                [ ( "id", id )
                ]

        browseToFetch : HM.TemplateVars -> List (Response -> Result String Affordance)
        browseToFetch vars =
            [ HM.browse [ "bggAPI" ] (ByType "ViewAction")
            , HM.browse [ "thing" ] (ByType "ViewAction") |> HM.fillIn vars
            ]
    in
    Up.retrieve
        { headers = Auth.credHeader creds
        , decoder = thingResponseDecoder
        , resMsg = resultDispatch
        , startAt = apiRoot
        , browsePlan = browseToFetch (buildVars thing_id)
        }


type alias SearchResult =
    { id : Affordance
    , things : List Thing
    }


searchDecoder : D.Decoder SearchResult
searchDecoder =
    D.succeed SearchResult
        |> custom (D.map (\u -> HM.link GET u) (D.field "id" D.string))
        |> required "things" (D.list thingDecoder)


search : Auth.Cred -> String -> (Result HM.Error ( Etag, SearchResult ) -> msg) -> Cmd msg
search creds query resultDispatch =
    let
        buildVars : String -> Dict.Dict String String
        buildVars q =
            Dict.fromList
                [ ( "query", q )
                ]

        browseToFetch : HM.TemplateVars -> List (Response -> Result String Affordance)
        browseToFetch vars =
            [ HM.browse [ "bggAPI" ] (ByType "ViewAction")
            , HM.browse [ "search" ] (ByType "FindAction") |> HM.fillIn vars
            ]
    in
    Up.retrieve
        { headers = Auth.credHeader creds
        , decoder = searchDecoder
        , resMsg = resultDispatch
        , startAt = apiRoot
        , browsePlan = browseToFetch (buildVars query)
        }



-- XXX We should allow batching in parallel with how BGG's API does
-- (or more batching?)
-- anyway, this is where we fix that interface


shotgunGames : Auth.Cred -> (a -> Maybe String) -> (a -> Result HM.Error ( Etag, Thing ) -> msg) -> List a -> Cmd msg
shotgunGames cred getId mkMsg list =
    let
        fetchForItem : a -> Cmd msg
        fetchForItem game =
            case getId game of
                Just id ->
                    fetchThingById cred id (mkMsg game)

                Nothing ->
                    Cmd.none
    in
    Cmd.batch (List.map fetchForItem list)
