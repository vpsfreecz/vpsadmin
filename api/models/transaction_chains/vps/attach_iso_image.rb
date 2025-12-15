module TransactionChains
  class Vps::AttachIsoImage < ::TransactionChain
    label 'ISO+'

    def link_chain(vps, iso_image)
      lock(vps)

      current_image_id = vps.iso_image_id

      append_t(Transactions::Vps::Define, args: [vps], kwargs: { iso_image: }) do |t|
        t.edit_before(vps, iso_image_id: current_image_id)
        next if included?

        t.just_create(vps.log(:attach_iso_image, { id: iso_image.id, name: iso_image.name }))
      end

      append_t(Transactions::Vps::AttachIsoImage, args: [vps, iso_image])

      vps.update!(iso_image:)
      vps
    end
  end
end
