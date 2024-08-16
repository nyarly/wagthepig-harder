port module State exposing (
  store, clear,
  onStoreChange, asString, loadAll, fromState, fromChange)

import Json.Decode as D exposing (Value)
import Dict exposing (Dict)

asString : Value -> Maybe String
asString value =
  D.decodeValue D.string value
  |> Result.toMaybe

store : String -> Value -> Cmd msg
store name value =
  storeCache (name, Just value)

clear : String -> Cmd msg
clear name =
  storeCache (name, Nothing)

loadAll : Value -> Dict String Value
loadAll localValues =
  D.decodeValue (D.dict D.value) localValues
  |> Result.mapError (\e -> Debug.log (D.errorToString e))
  |> Result.withDefault Dict.empty

fromState : String -> Result D.Error (Dict String Value) -> (String -> Maybe val) -> Maybe val
fromState name fromStore toVal =
    fromStore
    |> Result.toMaybe -- XXX ewwww
    |> Maybe.andThen (Dict.get name)
    |> Maybe.andThen asString
    |> Maybe.andThen toVal

fromChange : String -> (String, Value) -> (String -> Maybe val) -> Maybe val
fromChange name (changed, value) toVal =
  if (name /= changed) then
    Nothing
  else
    asString value
    |> Maybe.andThen toVal

port storeCache : (String, Maybe Value) -> Cmd msg

port onStoreChange : ((String, Value) -> msg) -> Sub msg
