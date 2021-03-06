<script>
import _ from 'underscore';
import DeprecatedModal from '~/vue_shared/components/deprecated_modal.vue';
import { s__, sprintf } from '~/locale';

export default {
  components: {
    DeprecatedModal,
  },
  props: {
    deleteUserUrl: {
      type: String,
      required: false,
      default: '',
    },
    blockUserUrl: {
      type: String,
      required: false,
      default: '',
    },
    deleteContributions: {
      type: Boolean,
      required: false,
      default: false,
    },
    username: {
      type: String,
      required: false,
      default: '',
    },
    csrfToken: {
      type: String,
      required: false,
      default: '',
    },
  },
  data() {
    return {
      enteredUsername: '',
    };
  },
  computed: {
    title() {
      const keepContributionsTitle = s__('AdminUsers|Delete User %{username}?');
      const deleteContributionsTitle = s__('AdminUsers|Delete User %{username} and contributions?');

      return sprintf(
        this.deleteContributions ? deleteContributionsTitle : keepContributionsTitle,
        {
          username: `'${_.escape(this.username)}'`,
        },
        false,
      );
    },
    text() {
      const keepContributionsText = s__(`AdminArea|
          You are about to permanently delete the user %{username}.
          Issues, merge requests, and groups linked to them will be transferred to a system-wide "Ghost-user".
          To avoid data loss, consider using the %{strong_start}block user%{strong_end} feature instead.
          Once you %{strong_start}Delete user%{strong_end}, it cannot be undone or recovered.`);

      const deleteContributionsText = s__(`AdminArea|
          You are about to permanently delete the user %{username}.
          This will delete all of the issues, merge requests, and groups linked to them.
          To avoid data loss, consider using the %{strong_start}block user%{strong_end} feature instead.
          Once you %{strong_start}Delete user%{strong_end}, it cannot be undone or recovered.`);
      return sprintf(
        this.deleteContributions ? deleteContributionsText : keepContributionsText,
        {
          username: `<strong>${_.escape(this.username)}</strong>`,
          strong_start: '<strong>',
          strong_end: '</strong>',
        },
        false,
      );
    },
    confirmationTextLabel() {
      return sprintf(
        s__('AdminUsers|To confirm, type %{username}'),
        {
          username: `<code>${_.escape(this.username)}</code>`,
        },
        false,
      );
    },
    primaryButtonLabel() {
      const keepContributionsLabel = s__('AdminUsers|Delete user');
      const deleteContributionsLabel = s__('AdminUsers|Delete user and contributions');

      return this.deleteContributions ? deleteContributionsLabel : keepContributionsLabel;
    },
    secondaryButtonLabel() {
      return s__('AdminUsers|Block user');
    },
    canSubmit() {
      return this.enteredUsername === this.username;
    },
  },
  methods: {
    onCancel() {
      this.enteredUsername = '';
    },
    onSecondaryAction() {
      const { form } = this.$refs;

      form.action = this.blockUserUrl;
      this.$refs.method.value = 'put';

      form.submit();
    },
    onSubmit() {
      this.$refs.form.submit();
      this.enteredUsername = '';
    },
  },
};
</script>

<template>
  <deprecated-modal
    id="delete-user-modal"
    :title="title"
    :text="text"
    :primary-button-label="primaryButtonLabel"
    :secondary-button-label="secondaryButtonLabel"
    :submit-disabled="!canSubmit"
    kind="danger"
    @submit="onSubmit"
    @cancel="onCancel"
  >
    <template
      slot="body"
      slot-scope="props"
    >
      <p v-html="props.text"></p>
      <p v-html="confirmationTextLabel"></p>
      <form
        ref="form"
        :action="deleteUserUrl"
        method="post"
      >
        <input
          ref="method"
          type="hidden"
          name="_method"
          value="delete"
        />
        <input
          :value="csrfToken"
          type="hidden"
          name="authenticity_token"
        />
        <input
          v-model="enteredUsername"
          type="text"
          name="username"
          class="form-control"
          aria-labelledby="input-label"
          autocomplete="off"
        />
      </form>
    </template>
    <template slot="secondary-button">
      <button
        :disabled="!canSubmit"
        type="button"
        class="btn js-secondary-button btn-warning"
        data-dismiss="modal"
        @click="onSecondaryAction"
      >
        {{ secondaryButtonLabel }}
      </button>
    </template>
  </deprecated-modal>
</template>
