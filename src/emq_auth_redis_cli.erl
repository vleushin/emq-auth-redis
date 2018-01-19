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

-module(emq_auth_redis_cli).

-behaviour(ecpool_worker).

-include("emq_auth_redis.hrl").

-include_lib("emqttd/include/emqttd.hrl").

-define(ENV(Key, Opts), proplists:get_value(Key, Opts)).

-export([connect/1, q/3]).

%%--------------------------------------------------------------------
%% Redis Connect/Query
%%--------------------------------------------------------------------

connect(Opts) ->
  eredis:start_link(?ENV(host, Opts),
    ?ENV(port, Opts),
    ?ENV(database, Opts),
    ?ENV(password, Opts),
    no_reconnect).

%% Redis Query.
-spec(q(string(), string(), mqtt_client()) -> {ok, undefined | binary() | list()} | {error, atom() | binary()}).
q(CmdStr, Password, Client) ->
  Cmd = string:tokens(replvar(CmdStr, Password, Client), " "),
  ecpool:with_client(?APP, fun(C) -> eredis:q(C, Cmd) end).

replvar(Cmd, Password, #mqtt_client{client_id = ClientId, username = Username}) ->
  replvar_(replvar_(replvar_(Cmd, "%u", Username), "%c", ClientId), "%p", Password).

replvar_(S, _Var, undefined) ->
  S;
replvar_(S, Var, Val) ->
  re:replace(S, Var, Val, [{return, list}]).

