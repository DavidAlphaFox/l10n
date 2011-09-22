% vim: set filetype=erlang shiftwidth=4 tabstop=4 expandtab tw=80:

%%% =====================================================================
%%%   Copyright 2011 Uvarov Michael 
%%%
%%%   Licensed under the Apache License, Version 2.0 (the "License");
%%%   you may not use this file except in compliance with the License.
%%%   You may obtain a copy of the License at
%%%
%%%       http://www.apache.org/licenses/LICENSE-2.0
%%%
%%%   Unless required by applicable law or agreed to in writing, software
%%%   distributed under the License is distributed on an "AS IS" BASIS,
%%%   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%%   See the License for the specific language governing permissions and
%%%   limitations under the License.
%%%
%%% $Id$
%%%
%%% @copyright 2010-2011 Michael Uvarov
%%% @author Michael Uvarov <freeakk@gmail.com>
%%% =====================================================================

%%% @private
-module(l10n_spawn_server).

-export([start_link/1]).
-export([init/1, terminate/2, 
    handle_call/3, handle_info/2]).
%% Exported Client's Functions
-export([find_store/2, reload_store/2, get_list/1]).

-behavior(gen_server).

-define(CFG_TBLNAME_STORES, 'l10n_stores').
-record(state, {table, domain}).

%% Operation & Maintenance API
start_link(Domain) ->
    Arguments = [Domain],
    Opts = [],
    Name = Domain:get_name('server'),
    gen_server:start_link({local, Name}, ?MODULE, Arguments, Opts).

init([D]) ->
    process_flag(trap_exit, true),
    E = ets:new(D:get_name('table'), []),
    {ok, #state{table=E, domain=D}}.

terminate(_Reason, _LoopData) ->
    ok.


handle_call({'find_store', Locale}, _From, LoopData=#state{table=E, domain=D}) ->
    Reply = lookup_store(Locale, E, D),
    {reply, Reply, LoopData};

handle_call('get_list', _From, LoopData=#state{table=E}) ->
    Reply = l10n_utils:get_keys(E),
    {reply, Reply, LoopData}.

handle_info({'EXIT', Pid, Reason}, LoopData=#state{table=E}) -> 
    [[Key]] = ets:match(E, {'$1', Pid}),
    ets:delete(E, Key),
    {noreply, LoopData}.
    
%%
%% API
%%

find_store(Domain, Locale) ->
    Pid = Domain:get_name('server'),
    gen_server:call(Pid, {'find_store', Locale}).

reload_store(Domain, Locale) ->
    P = find_store(Domain, Locale),
    case l10n_store_server:get_locale(P) of
    Locale ->
        l10n_store_server:stop(P),
        find_store(Domain, Locale),
        ok;
    _ ->
        'server_is_parent'
    end.
    

get_list(Domain) ->
    Pid = Domain:get_name('server'),
    gen_server:call(Pid, 'get_list').
        

%%
%% Server API
%%

spawn_store('root'=Locale, E, D) ->
    {ok, Pid} = l10n_store_server:start_link(D, Locale),
    ets:insert(E, {Locale, Pid}),
    Pid;
    
spawn_store(Locale, E, D) ->
    Pid = case D:is_available(Locale) of
        true ->
            % Load data from the file
            {ok, Pid2} = l10n_store_server:start_link(D, Locale),
            Pid2;
        false ->
            % Link to my parent
            PLocale = l10n_locale:get_parent_locale(Locale),
            lookup_store(PLocale, E, D)
        end,
    ets:insert(E, {Locale, Pid}),
    Pid.

lookup_store(Locale, E, D) ->
    try ets:lookup_element(E, Locale, 2)
    catch error:badarg ->
        spawn_store(Locale, E, D)
    end.
