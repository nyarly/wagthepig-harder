module LocalUtilities exposing (..)

import Http exposing (Resolver)
import Hypermedia exposing (Affordance, Method(..), Response, methodName)
import Task exposing (Task, andThen)


type alias AffordanceExtractor =
    ResponseToResult Affordance


type alias ResponseToResult a =
    Response -> Result String a


type alias RzToRes x a =
    Http.Response String -> Result x a


browseFrom : Affordance -> List AffordanceExtractor -> List Http.Header -> Http.Body -> ResponseToResult a -> Task Http.Error a
browseFrom start extractors headers body makeRes =
    let
        nextHop ex task =
            task |> andThen (follow headers Http.emptyBody ex)
    in
    List.foldl nextHop (Task.succeed start) extractors
        |> andThen (follow headers body makeRes)


follow : List Http.Header -> Http.Body -> ResponseToResult a -> Affordance -> Task Http.Error a
follow headers body makeRes aff =
    Http.task
        { method = methodName aff.method
        , url = aff.uri
        , body = body
        , timeout = Nothing
        , resolver = baseResolver makeRes
        , headers = headers
        }


baseResolver : ResponseToResult value -> Resolver Http.Error value
baseResolver extractValue =
    Http.stringResolver <| baseRzToRes extractValue


baseRzToRes : ResponseToResult a -> RzToRes Http.Error a
baseRzToRes extractValue =
    \response ->
        case response of
            Http.BadUrl_ url ->
                Err (Http.BadUrl url)

            Http.Timeout_ ->
                Err Http.Timeout

            Http.NetworkError_ ->
                Err Http.NetworkError

            -- Http.BadStatus means that we cannot extract knowledge from non-2xx responses
            -- Or we could build a Response and pass it to extractValue in both cases;
            -- would need to review existing uses
            Http.BadStatus_ metadata _ ->
                Err (Http.BadStatus metadata.statusCode)

            Http.GoodStatus_ metadata body ->
                Result.mapError Http.BadBody (extractValue (Response metadata.statusCode metadata.headers body))
