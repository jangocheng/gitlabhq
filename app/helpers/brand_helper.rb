module BrandHelper
  def brand_title
    'GitLab Enterprise Edition'
  end

  def brand_image
    image_tag 'brand_logo.png'
  end

  def brand_text
    default_text =<<eos
### GitLab is open source software to collaborate on code.

Manage git repositories with fine grained access controls that keep your code secure.
Perform code reviews and enhance collaboration with merge requests.
Each project can also have an issue tracker and a wiki.

Used by more than 50,000 organizations, GitLab is the most popular solution to manage git repositories on-premises.
Read more about GitLab at #{link_to "www.gitlab.com", "https://www.gitlab.com/", target: "_blank"}.
eos
    markdown default_text
  end
end
