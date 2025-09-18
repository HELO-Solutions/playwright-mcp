/**
 * Copyright (c) Microsoft Corporation.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { zodToJsonSchema } from 'zod-to-json-schema';

import type { z } from 'zod';
import type * as mcpServer from './server.js';

export type ToolSchema<Input extends z.Schema> = {
  name: string;
  title: string;
  description: string;
  inputSchema: Input;
  type: 'readOnly' | 'destructive';
};

export function toMcpTool(tool: ToolSchema<any>): mcpServer.Tool {
  const jsonSchema = zodToJsonSchema(tool.inputSchema, { strictUnions: true }) as mcpServer.Tool['inputSchema'];

  // Provider compatibility: some providers require `required` to list every property key.
  // Normalize the root object schema to include all property keys in `required`.
  if (
    jsonSchema &&
    typeof jsonSchema === 'object' &&
    (jsonSchema as any).type === 'object' &&
    (jsonSchema as any).properties &&
    typeof (jsonSchema as any).properties === 'object'
  ) {
    const propertyKeys = Object.keys((jsonSchema as any).properties);
    if (propertyKeys.length > 0)
      (jsonSchema as any).required = propertyKeys;
  }

  return {
    name: tool.name,
    description: tool.description,
    inputSchema: jsonSchema,
    annotations: {
      title: tool.title,
      readOnlyHint: tool.type === 'readOnly',
      destructiveHint: tool.type === 'destructive',
      openWorldHint: true,
    },
  };
}
