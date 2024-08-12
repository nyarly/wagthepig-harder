module Api exposing (Cred, loadCred, storageField, storeCred, login, accountID, logout, get, post, put, delete)

import Dict exposing (Dict)
import Http exposing (Body, Resolver)
import Task exposing (Task, andThen)
import Json.Decode as D exposing (Decoder, Value, decodeString, field)
import Json.Encode as E

import State

{-
-- CRED
This token should never be rendered to the end user, and with this API, it
can't be!
-}
type alias Cred = Maybe Credentials

type alias Credentials =
  { accountID: String
  , token: String
  }

storageField : String
storageField =
  "credentials"

loadCred : String -> Cred
loadCred value =
  D.decodeString credDecoder value
  |> Result.mapError D.errorToString
  |> Debug.log "loaded cred"
  |> Result.toMaybe

credHeader : Credentials -> Http.Header
credHeader cred =
  Http.header "authorization" cred.token -- Should be something like: ("Token " ++ cred.token)

{-| It's important that this is never exposed!
We expose `login`, `loadCred` and request functions instead, so we can be certain that if anyone
ever has access to a `Cred` value, it came from either the login API endpoint
or was passed in via flags.
-}
credDecoder : Decoder Credentials
credDecoder =
  D.map2 Credentials
    (D.field "accountID" D.string)
    (D.field "token" D.string)

encodeCred : Credentials -> Value
encodeCred cred =
  E.object
  [ ("accountID", E.string cred.accountID )
  , ("token", E.string cred.token )
  ]

storeCred : Cred -> Cmd msg
storeCred cred =
  case cred of
    Just c -> State.store storageField (encodeCred c)
    Nothing -> State.clear storageField

login : String -> String -> ResToMsg Http.Error Cred msg -> Cmd msg
login email password expect =
  Task.attempt expect
  (follow Nothing "GET" "/api"  Http.emptyBody rootExtractor
   |> andThen ( \links -> case (Dict.get "authenticate" links) of
     Just link -> follow Nothing "POST" link (Http.jsonBody (requestJson email password)) (credExtractor email)
     Nothing -> Task.fail (Http.BadBody "No authenticate link!")
     ))

accountID : Cred -> String
accountID cred =
  case cred of
    Just c -> c.accountID
    Nothing -> ""

{-
musing:
what if there were a "http plan":
creds
expect
[linkExtractor] = (name, (HeadersAndBodyToRes x a) <| (a -> String) -- extracts just the link from the response)
(method body makeRes toMsg)

-}

credExtractor : String -> Headers -> any -> (Result String Cred)
credExtractor email headers _ = -- XXX should use the body to get accountID
  case (Dict.get "set-authorization" headers) of
    Just token -> Ok (Just (Credentials email token))
    Nothing -> Err "no set-authorization header"

requestJson : String -> String -> Value
requestJson email password =
  E.object
    [ ( "email", E.string email )
    , ( "password", E.string password )
    ]

logout : Cmd msg
logout =
  State.clear storageField

-- HTTP

type alias Headers = (Dict String String)
type alias HeadersAndBodyToRes x a = (Headers -> String -> (Result x a))
type alias BodyToRes x a = (String -> (Result x a))
type alias RzToRes x a = (Http.Response String -> Result x a)
type alias ResToMsg x a msg = (Result x a -> msg)

{-
reasoning is that:

Task.attempt ResToMsg Http.task { resolver = stringResolver RzToRes }
is equivalent to
Http.request { expectStringResponse ResToMsg RzToRes }

and having `follow` lets us chase links if wanted
-}

jsonRequest : Cred -> String -> String -> Body -> Decoder a -> ResToMsg Http.Error a msg -> Cmd msg
jsonRequest maybeCred method url body decoder toMsg =
  let
    toRes = (\b -> Result.mapError D.errorToString (D.decodeString decoder  b))
  in
    request maybeCred method url Http.emptyBody toRes toMsg

request : Cred -> String -> String -> Body -> BodyToRes String a -> ResToMsg Http.Error a msg -> Cmd msg
request maybeCred method url body makeRes toMsg =
  Task.attempt toMsg
    (follow maybeCred method url body (\_ b-> makeRes b))

follow :  Cred -> String -> String -> Body -> HeadersAndBodyToRes String a -> Task Http.Error a
follow maybeCred method url body makeRes =
    Http.task
    { method = method
    , url = url
    , body = body
    , timeout = Nothing
    , resolver = baseResolver makeRes
    , headers =
      case maybeCred of
        Just cred ->
          [ credHeader cred ]
        Nothing ->
          []
    }



get :  Cred -> String -> Decoder a -> ResToMsg Http.Error a msg -> Cmd msg
get maybeCred url decoder toMsg =
  jsonRequest maybeCred "GET" url Http.emptyBody decoder toMsg

put :  Cred -> String -> Body -> Decoder a -> ResToMsg Http.Error a msg -> Cmd msg
put maybeCred url body decoder toMsg =
  jsonRequest maybeCred "PUT" url body decoder toMsg

post :  Cred -> String -> Body -> Decoder a -> ResToMsg Http.Error a msg -> Cmd msg
post maybeCred url body decoder toMsg =
  jsonRequest maybeCred "POST" url body decoder toMsg

delete :  Cred -> String -> Decoder a -> ResToMsg Http.Error a msg -> Cmd msg
delete maybeCred url  decoder toMsg =
  jsonRequest maybeCred "DELETE" url Http.emptyBody decoder toMsg


bodyRzToRes : (String -> (Result String value)) -> RzToRes Http.Error value
bodyRzToRes extractBody =
  baseRzToRes (\_ body -> extractBody body)


baseRzToRes : HeadersAndBodyToRes String a -> RzToRes Http.Error a
baseRzToRes extractValue =
    \response ->
        case response of
          Http.BadUrl_ url ->
            Err (Http.BadUrl url)

          Http.Timeout_ ->
            Err Http.Timeout

          Http.NetworkError_ ->
            Err Http.NetworkError

          Http.BadStatus_ metadata _->
            Err (Http.BadStatus metadata.statusCode)
          Http.GoodStatus_ metadata body ->
            Result.mapError Http.BadBody (extractValue metadata.headers body)

baseResolver : ((Dict String String) -> String -> (Result String value)) -> Resolver Http.Error value
baseResolver extractValue =
    Http.stringResolver <| baseRzToRes extractValue


rootExtractor : any -> String -> (Result String (Dict String String))
rootExtractor _ body =
    Result.mapError D.errorToString (decodeString (D.dict D.string) body)

rootResolver : Resolver Http.Error (Dict String String)
rootResolver =
  baseResolver (\_ body ->
    Result.mapError D.errorToString (decodeString (D.dict D.string) body)
  )

-- ERRORS


addServerError : List String -> List String
addServerError list =
  "Server error" :: list


errorsDecoder : Decoder (List String)
errorsDecoder =
  D.keyValuePairs (D.list D.string)
  |> D.map (List.concatMap fromPair)

fromPair : ( String, List String ) -> List String
fromPair ( field, errors ) =
  List.map (\error -> field ++ " " ++ error) errors
