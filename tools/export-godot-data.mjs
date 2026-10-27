// Refresh the editable Godot baseline resources from the original web prototype.
// Running this intentionally overwrites godot/data/world.tres; keep custom edits first.
import {mkdir, writeFile} from 'node:fs/promises';
import {initial, citizenEvents} from '../world.js';
const quote = JSON.stringify;
const actions = [
  ['farm', '组织耕种', '粮食+7，生态−2', {food: 7, ecology: -2}],
  ['mediate', '调解争端', '安定+6，粮食−1', {peace: 6, food: -1}],
  ['build', '建设集市', '繁荣+6，生态−3', {trade: 6, ecology: -3}],
  ['restore', '修复林地', '生态+6，繁荣−2', {ecology: 6, trade: -2}],
  ['observe', '观察世界', '推进一轮，观察漂移', {}],
];
const lines = ['[gd_resource type="Resource" script_class="WorldConfig" load_steps=26 format=3]', ''];
for (const [id, file] of [['World', 'world_config'], ['City', 'city_definition'], ['Action', 'action_definition'], ['Event', 'citizen_event_definition']]) {
  lines.push(`[ext_resource type="Script" path="res://scripts/data/${file}.gd" id="${id}"]`);
}
const refs = {City: [], Action: [], Event: []};
function resource(kind, id, fields) {
  refs[kind].push(`SubResource(${quote(id)})`);
  lines.push('', `[sub_resource type="Resource" id=${quote(id)}]`, `script = ExtResource(${quote(kind)})`);
  for (const [key, value] of Object.entries(fields)) lines.push(`${key} = ${value}`);
}
const colors = [[0.65,0.61,0.39], [0.35,0.60,0.47], [0.36,0.57,0.64], [0.54,0.51,0.64], [0.65,0.65,0.40], [0.40,0.57,0.56]];
initial().cities.forEach((c, i) => resource('City', c.id, {
  id: quote(c.id), city_name: quote(c.name), start: `Vector2(${c.x}, ${c.y})`,
  velocity: `Vector2(${c.vx}, ${c.vy})`, lore: quote(c.lore),
  food: c.food, peace: c.peace, trade: c.trade, ecology: c.ecology,
  tint: `Color(${colors[i].join(', ')}, 1)`,
}));
actions.forEach(([id, title, description, effect]) => resource('Action', id, {
  id: quote(id), title: quote(title), description: quote(description), effect: quote(effect),
}));
citizenEvents.forEach(e => resource('Event', e.id, {
  id: quote(e.id), title: quote(e.name), condition: quote(e.condition), text: quote(e.text),
  effect: quote(e.effect), repeat: String(Boolean(e.repeat)), predicate: quote(e.id),
}));
lines.push('', '[resource]', 'script = ExtResource("World")');
for (const [kind, key] of [['City','cities'], ['Action','actions'], ['Event','events']]) {
  lines.push(`${key} = Array[ExtResource("${kind}")]([${refs[kind].join(', ')}])`);
}
await mkdir(new URL('../godot/data/', import.meta.url), {recursive: true});
await writeFile(new URL('../godot/data/world.tres', import.meta.url), lines.join('\n') + '\n');
console.log('Wrote godot/data/world.tres (6 cities, 5 actions, 10 events).');
