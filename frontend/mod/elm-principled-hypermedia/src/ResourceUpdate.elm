module ResourceUpdate exposing
    ( create
    , retrieve
    , update
    , delete
    , roundTrip
    , MakeMsg
    , Representation(..)
    , Etag
    , apiRoot
    , resultDispatch
    , taggedResultDispatch
    )

{-| The purpose of this module is to handle standard exchanges with a Hypermedia server.

We want to be able to

  - create a resource from whole cloth, and browse to "where to put it"
      - then either load the server's response
      - or fetch the response from the Location returned
  - browse to a resource based on a "nickname" stored in a FE route
  - edit and update (via a local affordance) a resource we have "in hand"

The core of this module are four functions: `create`, `retrieve`, `update` and `delete`.
What differentiates these from the usual is two things:

  - They operate on records, because the parts of HTTP requests are reasonably complicated.
  - They work from starting affordance,
    (generally an API root)
    and browse to their target with a list of OperationSelectors

The fields you'll find in these function records are:

    { resource : s -- your resource data
    , encode : s -> E.Value -- a function to encode your resource
    , startAt : Affordance -- the starting Affordance; usually `apiRoot`
    , headers : List Http.Header -- headers for requests; e.g. `Authorization`
    , etag : Maybe Etag -- if you got an Etag from a previous request, include it
    , browsePlan : List AffordanceExtractor -- a list of AffordanceExtractor (use `Hypermedia.browse`)
    , decoder : D.Decoder r -- a Decoder for the response
    , resMsg : ResToMsg HM.Error () msg -- map HTTP responses to your own msg
    }

Not all fields are accepted by all four functions - see examples.

One notable characteristic: the functions don't assert any requirments on the affordances and browsing;
what matters is whether you are sending data (or not) and whether you expect a response (or not.)
On one end of the spectrum, `update` sends data and expects data in response.
On the other end, `delete` invokes an endpoint without request data,
and only cares about the status of the response.
It happens that the primary HTTP verbs encapsulate each of the four cases that arise thereby.

@docs create
@docs retrieve
@docs update
@docs delete
@docs roundTrip


## Details Used by the Operation Functions

@docs MakeMsg
@docs Representation
@docs Etag
@docs apiRoot
@docs resultDispatch
@docs taggedResultDispatch

-}

import Dict
import Http
import Hypermedia as HM exposing (Affordance, Method(..), OperationSelector(..), Response)
import Json.Decode as D
import Json.Encode as E
import Task



{-

   consumers will need
   their own nickname type, that can be encoded and parsed from their Route
   their own resource type, with .update and .template fields (both Maybe Affordance) and the nickname
   encode function and decoder for the resource
   (assumed: the BE has an API For the resource that provides this data)

   encodeEvent : Resource -> E.Value
   decoder : D.Decoder Resource

   you'll want to define a few adaptors:

   makeMsg : Auth.Cred -> Up.Representation Resource -> Msg -- going to be a case
   nickToVars : nick -> Dict.Dict String String
   browseToIt : HM.TemplateVars -> List (Response -> Result String Affordance)

-}
{-
   makeMsg like....
   makeMsg cred rep =
     case rep of
       Up.Loc aff -> Entered cred (Url aff)
       Up.Res res out -> GotThing res out
       Up.Error err -> ErrGetThing err

   makeMsg = (then creds)
-}
{- The encodes the response from creating/updating a resource -}


{-| A response from the server - a location, the etag of the resource, or an error
-}
type Representation e r
    = Loc Affordance
    | Res Etag r
    | Error e


{-| Represents an Etag as used in conditional requests
-}
type alias Etag =
    Maybe String


etagHeader : Etag -> List Http.Header
etagHeader etag =
    case etag of
        Just e ->
            [ Http.header "Etag" e ]

        Nothing ->
            []


{-| Consumers of this module need to define a function of this shape.
-}
type alias MakeMsg e r msg =
    Representation e r -> msg


type alias ResToMsg e r msg =
    Result e r -> msg


{-| The default API root. A convenience for clients of servers that use this default.
-}
apiRoot : Affordance
apiRoot =
    HM.link HM.GET "/api"


{-| Quick production of a ResMsg

    resMsg =
        resultDispatch ErrGetEvent (\( etag, ps ) -> GotEvent etag ps)

-}
resultDispatch : (error -> a) -> (value -> a) -> Result error value -> a
resultDispatch fromErr fromOk =
    taggedResultDispatch (\_ -> fromErr) (\_ -> fromOk) ()


{-| Slighly more involved version of resultDispatch,
that allows you to soncer the request when
producing errors.
-}
taggedResultDispatch : (req -> error -> msg) -> (req -> value -> msg) -> req -> Result error value -> msg
taggedResultDispatch fromErr fromOk req res =
    case res of
        Ok v ->
            fromOk req v

        Err x ->
            fromErr req x


type alias Create s msg =
    { resource : s
    , etag : Maybe Etag
    , encode : s -> E.Value
    , resMsg : ResToMsg HM.Error () msg
    , startAt : Affordance
    , browsePlan : List AffordanceExtractor
    , headers : List Http.Header
    }


{-| Sending data to the backend, only caring if it was successfully received

    ResourceUpdate.create
        { resource = res
        , etag = Just etag
        , encode = encoder
        , startAt = aff
        , headers = Auth.credHeader creds
        , browsePlan = []
        , resMsg = resultDispatch ErrGetGame (\_ -> CreatedGame)
        }

-}
create : Create s msg -> Cmd msg
create { headers, resource, etag, encode, resMsg, startAt, browsePlan } =
    let
        etagH =
            Maybe.withDefault [] (Maybe.map etagHeader etag)

        trip =
            HM.browseFrom startAt browsePlan (etagH ++ headers) (resource |> encode >> Http.jsonBody) emptyResponse
    in
    Task.attempt resMsg trip


type alias Retrieve r msg =
    { decoder : D.Decoder r
    , resMsg : ResToMsg HM.Error ( Etag, r ) msg
    , startAt : Affordance
    , browsePlan : List AffordanceExtractor
    , headers : List Http.Header
    }


{-| Request data from the server without a payload

    ResourceUpdate.retrieve
        { headers = Auth.credHeader creds
        , decoder = decoder
        , resMsg = resultDispatch ErrGetGame (\( etag, ps ) -> GotGame etag ps)
        , startAt = apiRoot
        , browsePlan = browseToFetch (nickToVars creds event_id nick)
        }

-}
retrieve : Retrieve r msg -> Cmd msg
retrieve { headers, decoder, resMsg, startAt, browsePlan } =
    let
        trip =
            HM.browseFrom startAt browsePlan headers Http.emptyBody (modelRes decoder)
    in
    Task.attempt resMsg trip


type alias Update s r msg =
    { resource : s
    , etag : Maybe Etag
    , encode : s -> E.Value
    , decoder : D.Decoder r
    , resMsg : ResToMsg HM.Error ( Etag, r ) msg
    , startAt : Affordance
    , browsePlan : List AffordanceExtractor
    , headers : List Http.Header
    }


{-| Send data to the server and expect data in response

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

-}
update : Update s r msg -> Cmd msg
update { headers, resource, etag, encode, decoder, resMsg, startAt, browsePlan } =
    let
        etagH =
            Maybe.withDefault [] (Maybe.map etagHeader etag)

        trip =
            HM.browseFrom startAt browsePlan (etagH ++ headers) (resource |> encode >> Http.jsonBody) (putResponse decoder)
                |> Task.andThen followHop

        followHop rep =
            case rep of
                Hop url ->
                    HM.browseFrom (HM.link HM.GET url) [] headers Http.emptyBody (landPutResponse decoder)

                Got e res ->
                    Task.succeed ( e, res )
    in
    Task.attempt resMsg trip


type alias Delete msg =
    { resMsg : ResToMsg HM.Error () msg
    , startAt : Affordance
    , browsePlan : List AffordanceExtractor
    , headers : List Http.Header
    }


{-| When you're making an empty request of the server, and only care if it was successful

    ResourceUpdate.delete
        { resMsg = resultDispatch ErrGetEvent (\( etag, ps ) -> GotEvent etag ps)
        , startAt = aff
        , browsePlan = [] -- List AffordanceExtractor
        , headers = Auth.credHeader creds -- Auth.Cred
        }

-}
delete : Delete msg -> Cmd msg
delete { headers, resMsg, startAt, browsePlan } =
    let
        trip =
            HM.browseFrom startAt browsePlan headers Http.emptyBody emptyResponse
    in
    Task.attempt resMsg trip


type alias RoundTrip r msg =
    { encode : r -> E.Value
    , decoder : D.Decoder r
    , makeMsg : MakeMsg Http.Error r msg
    , browsePlan : List AffordanceExtractor
    , updateRes : r -> Result Http.Error ( r, Affordance )
    , headers : List Http.Header
    }


{-| Handle the whole fetch, modify, update cycle

updateRes is

    updateRes : r -> Result Http.Error ( r, Affordance )

and takes the decoded response and produces an updated resource and an extracted affordance to PUT the update to.
Neatly, this all takes place in one Task chain.

    updateRz lr =
        let
            rz =
                update lr.resource
        in
        case lr.update of
            Just aff ->
                Ok ( { lr | resource = rz }, aff )

            Nothing ->
                Err (Http.BadStatus 429)
    Up.roundTrip
        { encode = encoder
        , decoder = decoder
        , makeMsg = makeMsg
        , browsePlan = browseToFetch (nickToVars cred event_id nick)
        , updateRes = updateRz
        , headers = Auth.credHeader cred
        }

-}
roundTrip : RoundTrip rz msg -> Cmd msg
roundTrip { encode, decoder, makeMsg, browsePlan, updateRes, headers } =
    let
        doUpdate ( e, r ) =
            case updateRes r of
                Ok ( new, aff ) ->
                    Task.succeed ( e, new, aff )

                Err x ->
                    Task.fail x

        toMsg =
            handlePutResult makeMsg

        trip =
            HM.browseFrom (HM.link HM.GET "/api") browsePlan headers HM.emptyBody (modelRes decoder)
                |> Task.andThen doUpdate
                |> Task.andThen
                    (\( etag, resource, aff ) ->
                        HM.browseFrom aff [] (etagHeader etag ++ headers) (resource |> encode >> Http.jsonBody) (putResponse decoder)
                    )
    in
    Task.attempt toMsg trip


type HopOrResource r
    = Hop String
    | Got Etag r


type alias AffordanceExtractor =
    Response -> Result String Affordance


gotFromTuple : ( Etag, r ) -> HopOrResource r
gotFromTuple ( etag, r ) =
    Got etag r


modelRes : D.Decoder r -> { a | body : String, headers : HM.Headers } -> Result String ( Etag, r )
modelRes decoder res =
    let
        etag =
            Dict.get "etag" (Debug.log "headers" res.headers)
    in
    res.body
        |> D.decodeString decoder
        |> Result.map (\r -> ( etag, r ))
        |> Result.mapError D.errorToString


putResponse : D.Decoder r -> Response -> Result String (HopOrResource r)
putResponse decoder res =
    case res.status of
        200 ->
            modelRes decoder res
                |> Result.map gotFromTuple

        201 ->
            case Dict.get "location" res.headers of
                Just url ->
                    Ok (Hop url)

                Nothing ->
                    Err "Expected location of new resource"

        other ->
            Err ("Unexpected status sending resource: " ++ String.fromInt other)


emptyResponse : Response -> Result String ()
emptyResponse res =
    case res.status of
        200 ->
            Ok ()

        201 ->
            Ok ()

        other ->
            Err ("Unexpected status sending resource: " ++ String.fromInt other)


landPutResponse : D.Decoder r -> Response -> Result String ( Etag, r )
landPutResponse decoder res =
    case res.status of
        200 ->
            modelRes decoder res

        201 ->
            Err "Second 201; assuming a loop"

        other ->
            Err ("Unexpected status sending resource: " ++ String.fromInt other)


handlePutResult : MakeMsg e r msg -> Result e (HopOrResource r) -> msg
handlePutResult makeMsg res =
    makeMsg <|
        case res of
            Ok (Hop url) ->
                Loc (HM.link GET url)

            Ok (Got etag rs) ->
                Res etag rs

            Err err ->
                Error err
