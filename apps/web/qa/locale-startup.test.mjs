import test from 'node:test';import assert from 'node:assert/strict';
import {startupAccountId,startupLanguageChoice,startupAutomaticLanguage} from '../src/locale-startup.ts';
const storage=value=>({getItem:key=>value[key]??null});
test('saved account locale wins before first paint and never passes through IP or guest choice',()=>{
 const source=storage({'gw-user':'{"id":"account-a"}','gw-settings:account-a':'{"language":"ru"}','gw-language-choice':'auto'});assert.equal(startupAccountId(source),'account-a');assert.equal(startupLanguageChoice(source),'ru');
 assert.equal(startupLanguageChoice(storage({'gw-user':'{"id":"account-a"}','gw-settings:account-a':'{"language":"ru"}','gw-settings-pending:account-a':'{"language":"de"}'})),'de');
});
test('logged-out, corrupt and blocked storage use safe language defaults without authenticating identity',()=>{
 assert.equal(startupLanguageChoice(storage({'gw-language-choice':'ru'})),'ru');assert.equal(startupAccountId(storage({'gw-user':'broken'})),null);assert.equal(startupLanguageChoice({getItem(){throw Error('blocked');}}),'auto');
 assert.equal(startupLanguageChoice(storage({'gw-user':'{"id":"b"}','gw-settings:a':'{"language":"ru"}'})),'auto');
});
test('automatic locale reuses a recent country-only choice and expires invalid or stale data',()=>{
 const saved={language:'kk',country:'KZ',source:'ip',savedAt:Date.now()};assert.equal(startupAutomaticLanguage(storage({'gw-language-auto':JSON.stringify(saved)}),'en').language,'ru');assert.equal(startupAutomaticLanguage(storage({'gw-language-auto':JSON.stringify({...saved,savedAt:0})}),'ru').language,'ru');assert.equal(startupAutomaticLanguage(storage({'gw-language-auto':JSON.stringify({...saved,language:'bad'})}),'en').language,'en');
});

test('automatic Kazakh falls back to Russian while explicit saved Kazakh stays selectable',()=>{assert.equal(startupAutomaticLanguage(storage({}),'kk').language,'ru');assert.equal(startupLanguageChoice(storage({'gw-language-choice':'kk'})),'kk');});
