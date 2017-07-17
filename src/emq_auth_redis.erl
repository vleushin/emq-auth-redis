%%--------------------------------------------------------------------
%% Copyright (c) 2013-2017 EMQ Enterprise, Inc. (http://emqtt.io)
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emq_auth_redis).

-behaviour(emqttd_auth_mod).

-include("emq_auth_redis.hrl").

-include_lib("emqttd/include/emqttd.hrl").

-export([init/1, check/3, description/0]).

-define(UNDEFINED(S), (S =:= undefined)).

-record(state, {auth_cmd, super_cmd, hash_type}).

init({AuthCmd, SuperCmd, HashType}) ->
    {ok, #state{auth_cmd = AuthCmd, super_cmd = SuperCmd, hash_type = HashType}}.

check(#mqtt_client{username = Username}, Password, _State)
    when ?UNDEFINED(Username); ?UNDEFINED(Password) ->
    {error, username_or_password_undefined};

check(Client, Password, #state{auth_cmd = AuthCmd,
    super_cmd = SuperCmd,
    hash_type = HashType}) ->
    Result = case check_client_id(Client) of
                 ok -> case emq_auth_redis_cli:q(AuthCmd, Password, Client) of
                           {ok, PassHash} when is_binary(PassHash) ->
                               check_pass(PassHash, Password, HashType);
                           {ok, [undefined | _]} ->
                               ignore;
                           {ok, undefined} ->
                               ignore;
                           {ok, [PassHash]} ->
                               check_pass(PassHash, Password, HashType);
                           {ok, [PassHash, Salt | _]} ->
                               check_pass(PassHash, Salt, Password, HashType);
                           {error, Reason} ->
                               {error, Reason}
                       end;
                 _Error -> _Error
             end,
    case Result of
        ok -> {ok, is_superuser(SuperCmd, Password, Client)};
        Error -> Error
    end.

check_pass(PassHash, Password, HashType) ->
    check_pass(PassHash, hash(HashType, Password)).
check_pass(PassHash, Salt, Password, {pbkdf2, Macfun, Iterations, Dklen}) ->
    check_pass(PassHash, hash(pbkdf2, {Salt, Password, Macfun, Iterations, Dklen}));
check_pass(PassHash, Salt, Password, {salt, bcrypt}) ->
    check_pass(PassHash, hash(bcrypt, {Salt, Password}));
check_pass(PassHash, Salt, Password, {salt, HashType}) ->
    check_pass(PassHash, hash(HashType, <<Salt/binary, Password/binary>>));
check_pass(PassHash, Salt, Password, {HashType, salt}) ->
    check_pass(PassHash, hash(HashType, <<Password/binary, Salt/binary>>)).

check_pass(PassHash, PassHash) -> ok;
check_pass(_, _) -> {error, password_error}.

description() -> "Authentication with Redis".

hash(Type, Password) -> emqttd_auth_mod:passwd_hash(Type, Password).

-spec(is_superuser(undefined | list(), string(), mqtt_client()) -> boolean()).
is_superuser(undefined, _Password, _Client) ->
    false;
is_superuser("undefined", _Password, _Client) ->
    false;
is_superuser(<<"undefined">>, _Password, _Client) ->
    false;
is_superuser(SuperCmd, Password, Client) ->
    case emq_auth_redis_cli:q(SuperCmd, Password, Client) of
        {ok, undefined} -> false;
        {ok, <<"1">>} -> true;
        {ok, _Other} -> false;
        {error, _Error} -> false
    end.

% We expect ClientId to be in format username_someid to prevent ClientId abuse
check_client_id(#mqtt_client{username = Username, client_id = ClientId}) ->
    case byte_size(ClientId) =< byte_size(Username) + 1 of
        true ->
            {error, "Bad client id"};
        false ->
            ExpectedScope = {0, byte_size(Username) + 1},
            case binary:match(ClientId, <<Username/binary, "_">>, [{scope, ExpectedScope}]) of
                ExpectedScope ->
                    ok;
                _Rest ->
                    {error, "Bad client id"}
            end
    end.
