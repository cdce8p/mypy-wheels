# Mypy wheels

Repo to build custom mypy mypyc wheels.
Only used for personal tests.

Official mypy test wheels can be found at: https://github.com/mypyc/mypy_mypyc-wheels/


## How does it work?
* Each push to the [`cdce8p/mypy`](https://github.com/cdce8p/mypy) triggers a webhook.
* The `POST` request is send to an AWS API Gateway which calls a Lambda function.
* That in turn validates the data and sends another `POST` request to Github Actions
to trigger a [`repository_dispatch`](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#repository_dispatch) event.
* The workflow first checks if the wheels already exist as release in [mypyc/mypy_mypyc-wheels](https://github.com/mypyc/mypy_mypyc-wheels/) or this repo. If not, it creates a new tag which contains a new file called `mypy_commit`.
* This then triggers the `Build wheels` workflow.


## Setup

```bash
# Aliases
alias ta="terraform apply"
alias td="terraform destroy"

# Create Secret for data signature
ruby -rsecurerandom -e 'puts SecureRandom.hex(20)'
```

**Github PAT**  
Create (fine-grained) PAT token with `metadata:read` and `contents:read&write` permissions for the repo.
Add token as `PUSH_TOKEN` to Github Action secrets.

**Create `secrets.auto.tfvars`**  
```HCL
github_pat = <Github PAT>
sig_key = <Data signature key>
mail_source = <Sender email address>
mail_recipient = <Receiver email address>
```

**Setup webhook**  
* Add new webhook
    * `Payload URL`:  `<TF base_url output>/webhook`
    * `Content type`: `application/json`
    * `Secret`: `<Data signature key>`
    * Trigger on `push` event

**Setup AWS Lambda function**  
* Build lambda dependencies: run task `Pip build Lambda deps`.
* Create cloud infrastructure with Terraform: `ta`


### Refs

https://docs.github.com/webhooks-and-events/webhooks/webhook-events-and-payloads#push
https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#repository_dispatch
https://docs.github.com/en/rest/repos/repos?apiVersion=2022-11-28#create-a-repository-dispatch-event
https://docs.github.com/en/webhooks-and-events/webhooks/securing-your-webhooks
https://mainawycliffe.dev/blog/github-actions-trigger-via-webhooks/
