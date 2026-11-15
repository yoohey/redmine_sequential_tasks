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
    # frame of Redmine (header, menus, sidebar, footer). Only the issue stays.
    EMBED_STYLE = <<~CSS
      #header, #top-menu, #main-menu, #sidebar, #footer { display: none !important; }
      #wrapper, #main { margin: 0 !important; padding: 0 !important; min-width: 0 !important; }
      #content { width: auto !important; float: none !important; padding: 8px 12px !important; margin: 0 !important; }
      body { min-width: 0 !important; }
      #sticky-issue-header { display: none !important; }
    CSS

    # The request is for an iframe: Sec-Fetch-Dest says so for every navigation inside it (links, form sends,
    # redirects); the parameter sq_embed=1 is added to the first load, for browsers that do not send the header
    def view_layouts_base_html_head(context = {})
      request = context[:request] || context[:controller]&.request
      return '' unless request && embedded?(request)

      # The inline view of an issue (params root): its links open in the page that holds the frame (the issue page, or the side panel), not in the small frame
      base = request.params['root'].present? ? '<base target="_parent">' : ''
      %(#{base}<style id="sq-embed">#{EMBED_STYLE}</style>).html_safe
    end

    private

    def embedded?(request)
      request.headers['Sec-Fetch-Dest'] == 'iframe' || request.params['sq_embed'] == '1'
    end
  end
end
