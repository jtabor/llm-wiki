Search the wiki for pages and references matching the user's query. Use the wiki's index-based navigation (same traversal as `wiki-read`) and return clickable links.

**Setup:**
1. Get the query from `$ARGUMENTS`. If empty, ask the user what to search for.

---

**Delegate to `wiki-read`** with the following prompt (substitute the actual query):

> Search the wiki for pages relevant to: "<query>"
>
> Do not answer the question — instead, return a **search results list**. For every page that is relevant to the query:
>
> 1. Walk `$WIKI_ROOT/index.md` and all `projects/*/index.md` files to locate candidate pages. Follow links into concepts/, sources/, analyses/, codebases/, and pitfalls files as needed.
> 2. For each matching page, output:
>    - A clickable `nvim://wiki/<relative-path>/1` link to open the page (use the `wiki` slug, which resolves to `$WIKI_ROOT`)
>    - The page's title (first H1) and one-sentence description of what it covers
>    - Any specific section or line within it that is most relevant — link that too as `nvim://wiki/<relative-path>/<line>`
> 3. For any PDF source files referenced on a matched page, also include a `zathura:///absolute/path/to/file.pdf/<page>` link (0-indexed page) if a specific page is cited.
> 4. Format results as a markdown list, grouped by project, e.g.:
>
> ```
> ## hatchwing
> - [`concepts/device.md`](nvim://wiki/projects/hatchwing/concepts/device.md/1) — What a device entity is and its lifecycle
>   - relevant section: [line 42](nvim://wiki/projects/hatchwing/concepts/device.md/42)
>
> ## llm-wiki
> - [`concepts/session-tokens.md`](nvim://wiki/projects/llm-wiki/concepts/session-tokens.md/1) — How cc- tokens are injected and used
> ```
>
> If nothing matches, say so and return a link to the top-level index: [`index.md`](nvim://wiki/index.md/1).

---

Present the output from `wiki-read` directly to the user.
