module RedmineSequentialTasks
  class Hooks < Redmine::Hook::ViewListener
    # Under the description of an issue: the stage bar, and the view with this issue at the top
    def view_issues_show_description_bottom(context = {})
      caller_view = context[:hook_caller]
      %w[issues/sequential_task_bar issues/sequential_task_root_view].map do |partial|
        caller_view.send(:render, partial: partial, locals: context)
      end.join.html_safe
    end

    # In the form of a new issue (also when copying one, and again each time Redmine rebuilds the form for a new
    # tracker or project): the stage timeline, to plan the stages while creating
    def view_issues_form_details_bottom(context = {})
      issue = context[:issue]
      return '' unless issue&.new_record? && issue.project&.module_enabled?(:sequential_tasks)

      setting = SequentialTaskSetting.find_by(tracker_id: issue.tracker_id, enabled: true)
      return '' unless setting && setting.steps.any?

      context[:hook_caller].send(:render, partial: 'issues/sequential_task_new_plan',
                                          locals: { issue: issue, setting: setting, plan_params: context[:request]&.params&.dig(:sq_plan) })
    end

    # Creating an issue from the form: the days chosen on its stage timeline (not through the REST API, which keeps
    # the standard days)
    def controller_issues_new_before_save(context = {})
      controller = context[:controller]
      return if controller.nil? || controller.api_request?

      context[:issue].sequential_plan_override = self.class.plan_override(context[:params]&.dig(:sq_plan), context[:issue].tracker_id)
    end

    # { status_id => { days:, all: } } from the form's sq_plan, or nil when there is none or it was made for another
    # tracker (the form was rebuilt for a new tracker without its own values)
    def self.plan_override(plan, tracker_id)
      return nil unless plan.respond_to?(:[]) && plan[:tracker_id].to_s == tracker_id.to_s

      steps = plan[:steps]
      return nil unless steps.respond_to?(:each_pair)

      steps.each_pair.with_object({}) do |(status_id, values), out|
        next unless values.respond_to?(:[])

        out[status_id.to_i] = { days: values[:days], all: values[:all].to_s == '1' }
      end
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

    # A page shown in a frame of a page of this Redmine (the side panel, the floating window, the view of an issue and
    # its branches) is shown without Redmine's frame. Two ways to know it, as neither is enough on its own:
    # - on the server: the header Sec-Fetch-Dest: iframe (sent for every navigation inside the frame, links, form sends
    #   and redirects included), or the parameter sq_embed=1 on the first load. Browsers send Sec-Fetch-* headers to
    #   secure contexts only (HTTPS, localhost), so a Redmine on plain http:// gets no header: after a form sent
    #   inside the frame redirects (without the parameter), the frame would come back;
    # - in the page: a small script in <head> that adds the same style when the page is in a frame whose parent is
    #   this Redmine (same origin), before anything is drawn. It works on http:// too.
    def view_layouts_base_html_head(context = {})
      request = context[:request] || context[:controller]&.request
      return FRAME_SCRIPT unless request && embedded?(request)

      # The inline view of an issue (params root): its links open in the page that holds the frame (the issue page, or the side panel), not in the small frame
      base = request.params['root'].present? ? '<base target="_parent">' : ''
      float = request.params['sq_float'] == '1' ? %(<style id="sq-float">#{FLOAT_STYLE}</style>) : ''
      %(#{base}<style id="sq-embed">#{EMBED_STYLE}</style>#{float}).html_safe
    end

    # The style above, added by the page itself when it finds itself in a frame of this Redmine and the server did not
    # (no header: plain http://). A parent of another origin cannot be read: the page stays as it is there.
    FRAME_SCRIPT = <<~HTML.html_safe
      <script>(function () { try { if (window.parent === window || window.parent.location.origin !== window.location.origin || document.getElementById('sq-embed')) return; } catch (e) { return; }
        var s = document.createElement('style'); s.id = 'sq-embed'; s.textContent = #{EMBED_STYLE.gsub(/\s+/, ' ').strip.to_json}; document.head.appendChild(s); })();</script>
    HTML

    private

    def embedded?(request)
      request.headers['Sec-Fetch-Dest'] == 'iframe' || request.params['sq_embed'] == '1'
    end
  end
end
