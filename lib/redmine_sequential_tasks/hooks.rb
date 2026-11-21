module RedmineSequentialTasks
  class Hooks < Redmine::Hook::ViewListener
    # Under the description of an issue: the stage bar, and the view with this issue at the top
    def view_issues_show_description_bottom(context = {})
      caller_view = context[:hook_caller]
      %w[issues/sequential_task_bar issues/sequential_task_root_view].map do |partial|
        caller_view.send(:render, partial: partial, locals: context)
      end.join.html_safe
    end

    # What to hide when a page is shown inside the side panel of the project screen: the
    # frame of Redmine (header, menus, sidebar, footer). Only the issue stays. The issue's own "previous / next" links go
    # too: they follow the numbers, while the panel's buttons follow the rows of the screen.
    EMBED_STYLE = <<~CSS
      #header, #top-menu, #main-menu, #sidebar, #footer { display: none !important; }
      #wrapper, #main { margin: 0 !important; padding: 0 !important; min-width: 0 !important; }
      #content { width: auto !important; float: none !important; padding: 8px 12px !important; margin: 0 !important; }
      body { min-width: 0 !important; }
      #sticky-issue-header { display: none !important; }
      .next-prev-links { display: none !important; }
    CSS

    # In the floating window of the project screen (sq_float=1): the issue's own block (the yellow box: subject, author,
    # attributes, description, attachments, the stage timeline, subtasks, related issues) and nothing else of the page;
    # the view of the issue and its branches (a timeline in a frame) is left out too.
    # Inside it, the stage timeline comes right under the attributes, and a long description scrolls in its own box,
    # so the head and the stage timeline stay in view. Only the issue itself (#content > .issue): Redmine's sticky
    # title is a .issue too and stays hidden.
    FLOAT_STYLE = <<~CSS
      #content > :not(.issue):not(.flash) { display: none !important; }
      #content > .issue { margin: 0 !important; display: flex; flex-direction: column; }
      #content > .issue > .avatar-with-child { position: absolute; }
      #content > .issue > .avatar-with-child + div, #content > .issue > p.author { margin-left: 60px; } /* beside the avatar, as on the issue page */
      #content > .issue > .reaction { align-self: flex-end; } /* the reaction button at the right, as on the issue page (a float does not work in the column) */
      #content > .issue > hr, #content > .issue > .description, #content > .issue > p:not(.author), #content > .issue > .attachments { order: 2; }
      #content > .issue > hr:has(+ #issue_tree), #content > .issue > hr:has(+ #relations), #issue_tree, #relations { order: 3; }
      .sq-root-view { display: none !important; } /* the view of this issue and its branches: a timeline in a frame, too big for the window */
      #sq-stage-timeline { order: 1; margin-bottom: 4px !important; }
      /* the page is as tall as the window (if even the head and the stage timeline do not fit, the yellow box scrolls) */
      html, body { height: 100% !important; overflow: hidden !important; }
      #wrapper { height: 100% !important; min-height: 0 !important; }
      #main { min-height: 0 !important; overflow: hidden; }
      #content { overflow: auto; display: flex; flex-direction: column; min-height: 0; box-sizing: border-box; }
      #content > .issue { flex: 1 1 auto; min-height: 0; overflow: auto; position: relative; } /* what does not fit even with the description at a few lines scrolls inside the yellow box */
      #content > .issue > .description { flex: 1 1 auto; min-height: 4.5em; overflow: auto; }
      #content > .issue > :not(.description) { flex-shrink: 0; }
    CSS

    # The request is for an iframe: Sec-Fetch-Dest says so for every navigation inside it (links, form sends,
    # redirects); the parameter sq_embed=1 is added to the first load, for browsers that do not send the header
    def view_layouts_base_html_head(context = {})
      request = context[:request] || context[:controller]&.request
      return '' unless request && embedded?(request)

      # The inline view of an issue (params root): its links open in the page that holds the frame (the issue page, or the side panel), not in the small frame
      base = request.params['root'].present? ? '<base target="_parent">' : ''
      float = request.params['sq_float'] == '1' ? %(<style id="sq-float">#{FLOAT_STYLE}</style>) : ''
      %(#{base}<style id="sq-embed">#{EMBED_STYLE}</style>#{float}).html_safe
    end

    private

    def embedded?(request)
      request.headers['Sec-Fetch-Dest'] == 'iframe' || request.params['sq_embed'] == '1'
    end
  end
end
