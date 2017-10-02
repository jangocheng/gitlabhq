require 'spec_helper'

describe GroupsController do
  let(:user) { create(:user) }
  let(:admin) { create(:admin) }
  let(:group) { create(:group, :public) }
  let(:project) { create(:project, namespace: group) }
  let!(:group_member) { create(:group_member, group: group, user: user) }
  let!(:owner) { group.add_owner(create(:user)).user }
  let!(:master) { group.add_master(create(:user)).user }
  let!(:developer) { group.add_developer(create(:user)).user }
  let!(:guest) { group.add_guest(create(:user)).user }

  shared_examples 'member with ability to create subgroups' do
    it 'renders the new page' do
      sign_in(member)

      get :new, parent_id: group.id

      expect(response).to render_template(:new)
    end
  end

  shared_examples 'member without ability to create subgroups' do
    it 'renders the 404 page' do
      sign_in(member)

      get :new, parent_id: group.id

      expect(response).not_to render_template(:new)
      expect(response.status).to eq(404)
    end
  end

  describe 'GET #new' do
    context 'when creating subgroups', :nested_groups do
      [true, false].each do |can_create_group_status|
        context "and can_create_group is #{can_create_group_status}" do
          before do
            User.where(id: [admin, owner, master, developer, guest]).update_all(can_create_group: can_create_group_status)
          end

          [:admin, :owner].each do |member_type|
            context "and logged in as #{member_type.capitalize}" do
              it_behaves_like 'member with ability to create subgroups' do
                let(:member) { send(member_type) }
              end
            end
          end

          [:guest, :developer, :master].each do |member_type|
            context "and logged in as #{member_type.capitalize}" do
              it_behaves_like 'member without ability to create subgroups' do
                let(:member) { send(member_type) }
              end
            end
          end
        end
      end
    end
  end

  describe 'POST #create' do
    context 'when creating subgroups', :nested_groups do
      [true, false].each do |can_create_group_status|
        context "and can_create_group is #{can_create_group_status}" do
          context 'and logged in as Owner' do
            it 'creates the subgroup' do
              owner.update_attribute(:can_create_group, can_create_group_status)
              sign_in(owner)

              post :create, group: { parent_id: group.id, path: 'subgroup' }

              expect(response).to be_redirect
              expect(response.body).to match(%r{http://test.host/#{group.path}/subgroup})
            end
          end

          context 'and logged in as Developer' do
            it 'renders the new template' do
              developer.update_attribute(:can_create_group, can_create_group_status)
              sign_in(developer)

              previous_group_count = Group.count

              post :create, group: { parent_id: group.id, path: 'subgroup' }

              expect(response).to render_template(:new)
              expect(Group.count).to eq(previous_group_count)
            end
          end
        end
      end
    end

    context 'when creating a top level group' do
      before do
        sign_in(developer)
      end

      context 'and can_create_group is enabled' do
        before do
          developer.update_attribute(:can_create_group, true)
        end

        it 'creates the Group' do
          original_group_count = Group.count

          post :create, group: { path: 'subgroup' }

          expect(Group.count).to eq(original_group_count + 1)
          expect(response).to be_redirect
        end
      end

      context 'and can_create_group is disabled' do
        before do
          developer.update_attribute(:can_create_group, false)
        end

        it 'does not create the Group' do
          original_group_count = Group.count

          post :create, group: { path: 'subgroup' }

          expect(Group.count).to eq(original_group_count)
          expect(response).to render_template(:new)
        end
      end
    end
  end

  describe 'GET #index' do
    context 'as a user' do
      it 'redirects to Groups Dashboard' do
        sign_in(user)

        get :index

        expect(response).to redirect_to(dashboard_groups_path)
      end
    end

    context 'as a guest' do
      it 'redirects to Explore Groups' do
        get :index

        expect(response).to redirect_to(explore_groups_path)
      end
    end
  end

  describe 'GET #show' do
    context 'pagination' do
      let(:per_page) { 3 }

      before do
        allow(Kaminari.config).to receive(:default_per_page).and_return(per_page)
      end

      context 'with only projects' do
        let!(:other_project) { create(:project, :public, namespace: group) }
        let!(:first_page_projects) { create_list(:project, per_page, :public, namespace: group ) }

        it 'has projects on the first page' do
          get :show, id: group.to_param, sort: 'id_desc'

          expect(assigns(:children)).to contain_exactly(*first_page_projects)
        end

        it 'has projects on the second page' do
          get :show, id: group.to_param, sort: 'id_desc', page: 2

          expect(assigns(:children)).to contain_exactly(other_project)
        end
      end

      context 'with subgroups and projects', :nested_groups do
        let!(:first_page_subgroups) { create_list(:group,  per_page, :public,  parent: group) }
        let!(:other_subgroup) { create(:group, :public, parent: group) }
        let!(:next_page_projects) { create_list(:project, per_page, :public, namespace: group) }

        it 'contains all subgroups' do
          get :children, id: group.to_param, sort: 'id_asc', format: :json

          expect(assigns(:children)).to contain_exactly(*first_page_subgroups)
        end

        it 'contains the project and group on the second page' do
          get :children, id: group.to_param, sort: 'id_asc', page: 2, format: :json

          expect(assigns(:children)).to contain_exactly(other_subgroup, *next_page_projects.take(per_page - 1))
        end
      end
    end
  end

  describe 'GET #children' do
    context 'for projects' do
      let!(:public_project) { create(:project, :public, namespace: group) }
      let!(:private_project) { create(:project, :private, namespace: group) }

      context 'as a user' do
        before do
          sign_in(user)
        end

        it 'shows all children' do
          get :children, id: group.to_param, format: :json

          expect(assigns(:children)).to contain_exactly(public_project, private_project)
        end

        context 'being member of private subgroup' do
          it 'shows public and private children the user is member of' do
            group_member.destroy!
            private_project.add_guest(user)

            get :children, id: group.to_param, format: :json

            expect(assigns(:children)).to contain_exactly(public_project, private_project)
          end
        end
      end

      context 'as a guest' do
        it 'shows the public children' do
          get :children, id: group.to_param, format: :json

          expect(assigns(:children)).to contain_exactly(public_project)
        end
      end
    end

    context 'for subgroups', :nested_groups do
      let!(:public_subgroup) { create(:group, :public, parent: group) }
      let!(:private_subgroup) { create(:group, :private, parent: group) }
      let!(:public_project) { create(:project, :public, namespace: group) }
      let!(:private_project) { create(:project, :private, namespace: group) }

      context 'as a user' do
        before do
          sign_in(user)
        end

        it 'shows all children' do
          get :children, id: group.to_param, format: :json

          expect(assigns(:children)).to contain_exactly(public_subgroup, private_subgroup, public_project, private_project)
        end

        context 'being member of private subgroup' do
          it 'shows public and private children the user is member of' do
            group_member.destroy!
            private_subgroup.add_guest(user)
            private_project.add_guest(user)

            get :children, id: group.to_param, format: :json

            expect(assigns(:children)).to contain_exactly(public_subgroup, private_subgroup, public_project, private_project)
          end
        end
      end

      context 'as a guest' do
        it 'shows the public children' do
          get :children, id: group.to_param, format: :json

          expect(assigns(:children)).to contain_exactly(public_subgroup, public_project)
        end
      end

      context 'filtering children' do
        it 'expands the tree for matching projects' do
          project = create(:project, :public, namespace: public_subgroup, name: 'filterme')

          get :children, id: group.to_param, filter: 'filter', format: :json

          group_json = json_response.first
          project_json = group_json['children'].first

          expect(group_json['id']).to eq(public_subgroup.id)
          expect(project_json['id']).to eq(project.id)
        end

        it 'expands the tree for matching subgroups' do
          matched_group = create(:group, :public, parent: public_subgroup, name: 'filterme')

          get :children, id: group.to_param, filter: 'filter', format: :json

          group_json = json_response.first
          matched_group_json = group_json['children'].first

          expect(group_json['id']).to eq(public_subgroup.id)
          expect(matched_group_json['id']).to eq(matched_group.id)
        end

        it 'merges the trees correctly' do
          shared_subgroup = create(:group, :public, parent: group, path: 'hardware')
          matched_project_1 = create(:project, :public, namespace: shared_subgroup, name: 'mobile-soc')

          l2_subgroup = create(:group, :public, parent: shared_subgroup, path: 'broadcom')
          l3_subgroup = create(:group, :public,  parent: l2_subgroup, path: 'wifi-group')
          matched_project_2 = create(:project, :public, namespace: l3_subgroup, name: 'mobile')

          get :children, id: group.to_param, filter: 'mobile', format: :json

          shared_group_json = json_response.first
          expect(shared_group_json['id']).to eq(shared_subgroup.id)

          matched_project_1_json = shared_group_json['children'].detect { |child| child['type'] == 'project' }
          expect(matched_project_1_json['id']).to eq(matched_project_1.id)

          l2_subgroup_json = shared_group_json['children'].detect { |child| child['type'] == 'group' }
          expect(l2_subgroup_json['id']).to eq(l2_subgroup.id)

          l3_subgroup_json = l2_subgroup_json['children'].first
          expect(l3_subgroup_json['id']).to eq(l3_subgroup.id)

          matched_project_2_json = l3_subgroup_json['children'].first
          expect(matched_project_2_json['id']).to eq(matched_project_2.id)
        end

        it 'expands the tree upto a specified parent' do
          subgroup = create(:group, :public, parent: group)
          l2_subgroup = create(:group, :public, parent: subgroup)
          create(:project, :public, namespace: l2_subgroup, name: 'test')

          get :children, id: subgroup.to_param, filter: 'test', format: :json

          expect(response).to have_http_status(200)
        end

        it 'includes pagination headers' do
          2.times { |i| create(:group, :public, parent: public_subgroup, name: "filterme#{i}") }

          get :children, id: group.to_param, filter: 'filter', per_page: 1, format: :json

          expect(response).to include_pagination_headers
        end
      end

      context 'queries per rendered element', :request_store do
        # We need to make sure the following counts are preloaded
        # otherwise they will cause an extra query
        # 1. Count of visible projects in the element
        # 2. Count of visible subgroups in the element
        # 3. Count of members of a group
        let(:expected_queries_per_group) { 0 }
        let(:expected_queries_per_project) { 0 }

        def get_list
          get :children, id: group.to_param, format: :json
        end

        it 'queries the expected amount for a group row' do
          control = ActiveRecord::QueryRecorder.new { get_list }

          _new_group = create(:group, :public, parent: group)

          expect { get_list }.not_to exceed_query_limit(control).with_threshold(expected_queries_per_group)
        end

        it 'queries the expected amount for a project row' do
          control = ActiveRecord::QueryRecorder.new { get_list }
          _new_project = create(:project, :public, namespace: group)

          expect { get_list }.not_to exceed_query_limit(control).with_threshold(expected_queries_per_project)
        end

        context 'when rendering hierarchies' do
          # When loading hierarchies we load the all the ancestors for matched projects
          # in 1 separate query
          let(:extra_queries_for_hierarchies) { 1 }

          def get_filtered_list
            get :children, id: group.to_param, filter: 'filter', format: :json
          end

          it 'queries the expected amount when nested rows are increased for a group' do
            matched_group = create(:group, :public, parent: group, name: 'filterme')

            control = ActiveRecord::QueryRecorder.new { get_filtered_list }

            matched_group.update!(parent: public_subgroup)

            expect { get_filtered_list }.not_to exceed_query_limit(control).with_threshold(extra_queries_for_hierarchies)
          end

          it 'queries the expected amount when a new group match is added' do
            create(:group, :public, parent: public_subgroup, name: 'filterme')

            control = ActiveRecord::QueryRecorder.new { get_filtered_list }

            create(:group, :public, parent: public_subgroup, name: 'filterme2')
            create(:group, :public, parent: public_subgroup, name: 'filterme3')

            expect { get_filtered_list }.not_to exceed_query_limit(control).with_threshold(extra_queries_for_hierarchies)
          end

          it 'queries the expected amount when nested rows are increased for a project' do
            matched_project = create(:project, :public, namespace: group, name: 'filterme')

            control = ActiveRecord::QueryRecorder.new { get_filtered_list }

            matched_project.update!(namespace: public_subgroup)

            expect { get_filtered_list }.not_to exceed_query_limit(control).with_threshold(extra_queries_for_hierarchies)
          end
        end
      end
    end
  end

  describe 'GET #issues' do
    let(:issue_1) { create(:issue, project: project) }
    let(:issue_2) { create(:issue, project: project) }

    before do
      create_list(:award_emoji, 3, awardable: issue_2)
      create_list(:award_emoji, 2, awardable: issue_1)
      create_list(:award_emoji, 2, :downvote, awardable: issue_2)

      sign_in(user)
    end

    context 'sorting by votes' do
      it 'sorts most popular issues' do
        get :issues, id: group.to_param, sort: 'upvotes_desc'
        expect(assigns(:issues)).to eq [issue_2, issue_1]
      end

      it 'sorts least popular issues' do
        get :issues, id: group.to_param, sort: 'downvotes_desc'
        expect(assigns(:issues)).to eq [issue_2, issue_1]
      end
    end
  end

  describe 'GET #merge_requests' do
    let(:merge_request_1) { create(:merge_request, source_project: project) }
    let(:merge_request_2) { create(:merge_request, :simple, source_project: project) }

    before do
      create_list(:award_emoji, 3, awardable: merge_request_2)
      create_list(:award_emoji, 2, awardable: merge_request_1)
      create_list(:award_emoji, 2, :downvote, awardable: merge_request_2)

      sign_in(user)
    end

    context 'sorting by votes' do
      it 'sorts most popular merge requests' do
        get :merge_requests, id: group.to_param, sort: 'upvotes_desc'
        expect(assigns(:merge_requests)).to eq [merge_request_2, merge_request_1]
      end

      it 'sorts least popular merge requests' do
        get :merge_requests, id: group.to_param, sort: 'downvotes_desc'
        expect(assigns(:merge_requests)).to eq [merge_request_2, merge_request_1]
      end
    end
  end

  describe 'DELETE #destroy' do
    context 'as another user' do
      it 'returns 404' do
        sign_in(create(:user))

        delete :destroy, id: group.to_param

        expect(response.status).to eq(404)
      end
    end

    context 'as the group owner' do
      before do
        sign_in(user)
      end

      it 'schedules a group destroy' do
        Sidekiq::Testing.fake! do
          expect { delete :destroy, id: group.to_param }.to change(GroupDestroyWorker.jobs, :size).by(1)
        end
      end

      it 'redirects to the root path' do
        delete :destroy, id: group.to_param

        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe 'PUT update' do
    before do
      sign_in(user)
    end

    it 'updates the path successfully' do
      post :update, id: group.to_param, group: { path: 'new_path' }

      expect(response).to have_http_status(302)
      expect(controller).to set_flash[:notice]
    end

    it 'does not update the path on error' do
      allow_any_instance_of(Group).to receive(:move_dir).and_raise(Gitlab::UpdatePathError)
      post :update, id: group.to_param, group: { path: 'new_path' }

      expect(assigns(:group).errors).not_to be_empty
      expect(assigns(:group).path).not_to eq('new_path')
    end
  end

  describe '#ensure_canonical_path' do
    before do
      sign_in(user)
    end

    context 'for a GET request' do
      context 'when requesting groups at the root path' do
        before do
          allow(request).to receive(:original_fullpath).and_return("/#{group_full_path}")
          get :show, id: group_full_path
        end

        context 'when requesting the canonical path with different casing' do
          let(:group_full_path) { group.to_param.upcase }

          it 'redirects to the correct casing' do
            expect(response).to redirect_to(group)
            expect(controller).not_to set_flash[:notice]
          end
        end

        context 'when requesting a redirected path' do
          let(:redirect_route) { group.redirect_routes.create(path: 'old-path') }
          let(:group_full_path) { redirect_route.path }

          it 'redirects to the canonical path' do
            expect(response).to redirect_to(group)
            expect(controller).to set_flash[:notice].to(group_moved_message(redirect_route, group))
          end

          context 'when the old group path is a substring of the scheme or host' do
            let(:redirect_route) { group.redirect_routes.create(path: 'http') }

            it 'does not modify the requested host' do
              expect(response).to redirect_to(group)
              expect(controller).to set_flash[:notice].to(group_moved_message(redirect_route, group))
            end
          end

          context 'when the old group path is substring of groups' do
            # I.e. /groups/oups should not become /grfoo/oups
            let(:redirect_route) { group.redirect_routes.create(path: 'oups') }

            it 'does not modify the /groups part of the path' do
              expect(response).to redirect_to(group)
              expect(controller).to set_flash[:notice].to(group_moved_message(redirect_route, group))
            end
          end
        end
      end

      context 'when requesting groups under the /groups path' do
        context 'when requesting the canonical path' do
          context 'non-show path' do
            context 'with exactly matching casing' do
              it 'does not redirect' do
                get :issues, id: group.to_param

                expect(response).not_to have_http_status(301)
              end
            end

            context 'with different casing' do
              it 'redirects to the correct casing' do
                get :issues, id: group.to_param.upcase

                expect(response).to redirect_to(issues_group_path(group.to_param))
                expect(controller).not_to set_flash[:notice]
              end
            end
          end

          context 'show path' do
            context 'with exactly matching casing' do
              it 'does not redirect' do
                get :show, id: group.to_param

                expect(response).not_to have_http_status(301)
              end
            end

            context 'with different casing' do
              it 'redirects to the correct casing at the root path' do
                get :show, id: group.to_param.upcase

                expect(response).to redirect_to(group)
                expect(controller).not_to set_flash[:notice]
              end
            end
          end
        end

        context 'when requesting a redirected path' do
          let(:redirect_route) { group.redirect_routes.create(path: 'old-path') }

          it 'redirects to the canonical path' do
            get :issues, id: redirect_route.path

            expect(response).to redirect_to(issues_group_path(group.to_param))
            expect(controller).to set_flash[:notice].to(group_moved_message(redirect_route, group))
          end

          context 'when the old group path is a substring of the scheme or host' do
            let(:redirect_route) { group.redirect_routes.create(path: 'http') }

            it 'does not modify the requested host' do
              get :issues, id: redirect_route.path

              expect(response).to redirect_to(issues_group_path(group.to_param))
              expect(controller).to set_flash[:notice].to(group_moved_message(redirect_route, group))
            end
          end

          context 'when the old group path is substring of groups' do
            # I.e. /groups/oups should not become /grfoo/oups
            let(:redirect_route) { group.redirect_routes.create(path: 'oups') }

            it 'does not modify the /groups part of the path' do
              get :issues, id: redirect_route.path

              expect(response).to redirect_to(issues_group_path(group.to_param))
              expect(controller).to set_flash[:notice].to(group_moved_message(redirect_route, group))
            end
          end

          context 'when the old group path is substring of groups plus the new path' do
            # I.e. /groups/oups/oup should not become /grfoos
            let(:redirect_route) { group.redirect_routes.create(path: 'oups/oup') }

            it 'does not modify the /groups part of the path' do
              get :issues, id: redirect_route.path

              expect(response).to redirect_to(issues_group_path(group.to_param))
              expect(controller).to set_flash[:notice].to(group_moved_message(redirect_route, group))
            end
          end
        end
      end

      context 'for a POST request' do
        context 'when requesting the canonical path with different casing' do
          it 'does not 404' do
            post :update, id: group.to_param.upcase, group: { path: 'new_path' }

            expect(response).not_to have_http_status(404)
          end

          it 'does not redirect to the correct casing' do
            post :update, id: group.to_param.upcase, group: { path: 'new_path' }

            expect(response).not_to have_http_status(301)
          end
        end

        context 'when requesting a redirected path' do
          let(:redirect_route) { group.redirect_routes.create(path: 'old-path') }

          it 'returns not found' do
            post :update, id: redirect_route.path, group: { path: 'new_path' }

            expect(response).to have_http_status(404)
          end
        end
      end

      context 'for a DELETE request' do
        context 'when requesting the canonical path with different casing' do
          it 'does not 404' do
            delete :destroy, id: group.to_param.upcase

            expect(response).not_to have_http_status(404)
          end

          it 'does not redirect to the correct casing' do
            delete :destroy, id: group.to_param.upcase

            expect(response).not_to have_http_status(301)
          end
        end

        context 'when requesting a redirected path' do
          let(:redirect_route) { group.redirect_routes.create(path: 'old-path') }

          it 'returns not found' do
            delete :destroy, id: redirect_route.path

            expect(response).to have_http_status(404)
          end
        end
      end
    end

    def group_moved_message(redirect_route, group)
      "Group '#{redirect_route.path}' was moved to '#{group.full_path}'. Please update any links and bookmarks that may still have the old path."
    end
  end
end
